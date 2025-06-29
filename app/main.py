import logging
import signal
import sys
from datetime import datetime
from typing import Dict, List

import uvicorn
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Histogram, generate_latest
from pydantic import BaseModel

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Pydantic models
class HealthResponse(BaseModel):
    status: str
    timestamp: str
    version: str = "1.0.0"

class Item(BaseModel):
    id: int
    name: str
    description: str

class CreateItemRequest(BaseModel):
    name: str
    description: str

class ItemsResponse(BaseModel):
    items: List[Item]
    total: int

# Metrics
REQUEST_COUNT = Counter('fastapi_requests_total', 'Total requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('fastapi_request_duration_seconds', 'Request duration')

# In-memory storage
items_storage: List[Dict] = [
    {"id": 1, "name": "item1", "description": "First item"},
    {"id": 2, "name": "item2", "description": "Second item"},
    {"id": 3, "name": "item3", "description": "Third item"},
]

app = FastAPI(
    title="Production FastAPI Service",
    description="A simple production-ready FastAPI service",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["*"],
)

# Graceful shutdown handling
def signal_handler(signum, frame):
    logger.info(f"Received signal {signum}, shutting down gracefully")
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint for liveness probe"""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.utcnow().isoformat() + "Z"
    )


@app.get("/health/ready", response_model=HealthResponse)
async def readiness_check():
    """Readiness check endpoint"""
    return HealthResponse(
        status="ready",
        timestamp=datetime.utcnow().isoformat() + "Z"
    )


@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()


@app.get("/items", response_model=ItemsResponse)
async def get_items():
    """Get all items"""
    logger.info("Fetching all items")
    REQUEST_COUNT.labels(method="GET", endpoint="/items", status="200").inc()
    
    return ItemsResponse(
        items=[Item(**item) for item in items_storage],
        total=len(items_storage)
    )


@app.get("/items/{item_id}", response_model=Item)
async def get_item(item_id: int):
    """Get item by ID"""
    logger.info(f"Fetching item {item_id}")
    
    item = next((item for item in items_storage if item["id"] == item_id), None)
    if not item:
        REQUEST_COUNT.labels(method="GET", endpoint="/items/{id}", status="404").inc()
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Item {item_id} not found"
        )
    
    REQUEST_COUNT.labels(method="GET", endpoint="/items/{id}", status="200").inc()
    return Item(**item)


@app.post("/items", response_model=Item, status_code=status.HTTP_201_CREATED)
async def create_item(item_request: CreateItemRequest):
    """Create a new item"""
    logger.info(f"Creating item: {item_request.name}")
    
    # Generate new ID
    new_id = max([item["id"] for item in items_storage], default=0) + 1
    
    new_item = {
        "id": new_id,
        "name": item_request.name,
        "description": item_request.description
    }
    
    items_storage.append(new_item)
    REQUEST_COUNT.labels(method="POST", endpoint="/items", status="201").inc()
    
    logger.info(f"Created item with ID: {new_id}")
    return Item(**new_item)


@app.delete("/items/{item_id}")
async def delete_item(item_id: int):
    """Delete item by ID"""
    logger.info(f"Deleting item {item_id}")
    
    item_index = next(
        (index for index, item in enumerate(items_storage) if item["id"] == item_id), 
        None
    )
    
    if item_index is None:
        REQUEST_COUNT.labels(method="DELETE", endpoint="/items/{id}", status="404").inc()
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Item {item_id} not found"
        )
    
    deleted_item = items_storage.pop(item_index)
    REQUEST_COUNT.labels(method="DELETE", endpoint="/items/{id}", status="200").inc()
    
    logger.info(f"Deleted item: {deleted_item}")
    return {"message": f"Item {item_id} deleted successfully"}


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        log_level="info"
    )