"""
Service Authentication Middleware for AI Engine
JWT-based authentication for FastAPI endpoints
"""

import os
import jwt
import time
import logging
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List
from fastapi import HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

logger = logging.getLogger(__name__)

class ServiceAuthenticator:
    def __init__(self):
        self.service_secret = os.getenv('SERVICE_JWT_SECRET')
        self.service_name = os.getenv('SERVICE_NAME', 'ai-engine')
        self.enabled = os.getenv('SERVICE_AUTH_ENABLED', 'false').lower() == 'true'
        self.valid_issuers = ['api-gateway', 'ai-engine', 'vision-service']
        
        if self.enabled and not self.service_secret:
            logger.warning("⚠️ SERVICE_JWT_SECRET not set but authentication is enabled")
        
        logger.info(f"🔐 Service Authentication: {'ENABLED' if self.enabled else 'DISABLED'}")

    def validate_service_token(self, token: str, expected_audience: Optional[str] = None) -> Dict[str, Any]:
        """Validate incoming service JWT token"""
        if not self.enabled:
            return {"valid": True, "bypass": True}
        
        if not token:
            return {
                "valid": False,
                "error": "No service token provided",
                "code": "MISSING_TOKEN"
            }
        
        if not self.service_secret:
            return {
                "valid": False,
                "error": "Service authentication not properly configured",
                "code": "AUTH_CONFIG_ERROR"
            }
        
        try:
            # Decode and verify JWT
            decoded = jwt.decode(
                token,
                self.service_secret,
                algorithms=['HS256'],
                options={"verify_exp": True}
            )
            
            # Validate audience if specified
            if expected_audience and decoded.get('aud') != expected_audience:
                return {
                    "valid": False,
                    "error": f"Invalid token audience. Expected: {expected_audience}, Got: {decoded.get('aud')}",
                    "code": "INVALID_AUDIENCE"
                }
            
            # Validate issuer
            issuer = decoded.get('iss')
            if issuer not in self.valid_issuers:
                return {
                    "valid": False,
                    "error": f"Unknown service issuer: {issuer}",
                    "code": "UNKNOWN_ISSUER"
                }
            
            return {
                "valid": True,
                "payload": decoded,
                "issuer": issuer,
                "audience": decoded.get('aud')
            }
            
        except jwt.ExpiredSignatureError:
            return {
                "valid": False,
                "error": "Service token has expired",
                "code": "TOKEN_EXPIRED"
            }
        except jwt.InvalidTokenError as e:
            return {
                "valid": False,
                "error": f"Invalid service token: {str(e)}",
                "code": "INVALID_TOKEN"
            }
        except Exception as e:
            logger.error(f"Token validation error: {e}")
            return {
                "valid": False,
                "error": "Token validation failed",
                "code": "VALIDATION_ERROR"
            }

    def extract_token(self, request: Request) -> Optional[str]:
        """Extract token from request headers"""
        # Check Authorization header
        auth_header = request.headers.get('authorization')
        if auth_header and auth_header.startswith('Bearer '):
            return auth_header[7:]
        
        # Check custom service header
        return request.headers.get('x-service-token')

    def create_dependency(self, expected_audience: Optional[str] = None):
        """Create FastAPI dependency for service authentication"""
        def authenticate_service(request: Request):
            if not self.enabled:
                return {"bypass": True, "service": "bypass"}
            
            token = self.extract_token(request)
            validation = self.validate_service_token(token, expected_audience)
            
            if not validation["valid"]:
                raise HTTPException(
                    status_code=401,
                    detail={
                        "error": "Service Authentication Failed",
                        "message": validation["error"],
                        "code": validation["code"],
                        "timestamp": datetime.utcnow().isoformat()
                    }
                )
            
            return {
                "valid": True,
                "issuer": validation.get("issuer"),
                "audience": validation.get("audience"),
                "payload": validation.get("payload", {})
            }
        
        return authenticate_service

    def get_status(self):
        """Get authentication status"""
        return {
            "enabled": self.enabled,
            "service_name": self.service_name,
            "has_secret": bool(self.service_secret),
            "valid_issuers": self.valid_issuers
        }


# Global authenticator instance
service_auth = ServiceAuthenticator()

# FastAPI dependencies
def require_service_auth(expected_audience: str = None):
    """Dependency that requires valid service authentication"""
    return Depends(service_auth.create_dependency(expected_audience))

def optional_service_auth():
    """Dependency that optionally validates service authentication"""
    def authenticate_optional(request: Request):
        if not service_auth.enabled:
            return {"bypass": True}
        
        token = service_auth.extract_token(request)
        if not token:
            return {"authenticated": False, "reason": "no_token"}
        
        validation = service_auth.validate_service_token(token)
        if validation["valid"]:
            return {
                "authenticated": True,
                "issuer": validation["issuer"],
                "payload": validation["payload"]
            }
        else:
            return {
                "authenticated": False,
                "reason": validation["code"],
                "error": validation["error"]
            }
    
    return Depends(authenticate_optional)


# Middleware for request logging with service info
async def service_auth_middleware(request: Request, call_next):
    """Middleware to add service authentication info to request"""
    start_time = time.time()
    
    # Extract and validate service token
    if service_auth.enabled:
        token = service_auth.extract_token(request)
        if token:
            validation = service_auth.validate_service_token(token)
            request.state.service_auth = validation
        else:
            request.state.service_auth = {"valid": False, "error": "No token provided"}
    else:
        request.state.service_auth = {"bypass": True}
    
    # Process request
    response = await call_next(request)
    
    # Add processing time and service info to response headers
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    
    if hasattr(request.state, 'service_auth') and request.state.service_auth.get('valid'):
        response.headers["X-Service-Issuer"] = request.state.service_auth.get('issuer', 'unknown')
    
    return response


# Health check with service authentication
def create_authenticated_health_check():
    """Create health check endpoint that requires service authentication"""
    def health_check_with_auth(service_info = require_service_auth()):
        return {
            "status": "healthy",
            "service": "ai-engine",
            "timestamp": datetime.utcnow().isoformat(),
            "authenticated": not service_info.get("bypass", False),
            "issuer": service_info.get("issuer") if not service_info.get("bypass") else None
        }
    
    return health_check_with_auth


# Export the main components
__all__ = [
    'ServiceAuthenticator',
    'service_auth',
    'require_service_auth',
    'optional_service_auth',
    'service_auth_middleware',
    'create_authenticated_health_check'
]