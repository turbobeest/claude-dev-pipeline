# OpenSpec Proposal: User Authentication API

## Overview
This proposal defines the API specification for the user authentication system based on the requirements in the PRD.

## Authentication Endpoints

### POST /api/auth/register
Register a new user account.

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "firstName": "John",
  "lastName": "Doe"
}
```

**Response (201 Created):**
```json
{
  "success": true,
  "message": "Registration successful. Please check your email for verification.",
  "data": {
    "userId": "uuid-string",
    "email": "user@example.com",
    "emailVerified": false
  }
}
```

**Validation Rules:**
- Email must be valid format
- Password must be 8+ characters with uppercase, lowercase, number
- First name and last name are optional
- Email must be unique

### POST /api/auth/login
Authenticate user and return JWT token.

**Request Body:**
```json
{
  "email": "user@example.com", 
  "password": "SecurePass123!",
  "rememberMe": false
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "user": {
      "id": "uuid-string",
      "email": "user@example.com",
      "firstName": "John",
      "lastName": "Doe",
      "role": "user",
      "emailVerified": true
    },
    "tokens": {
      "accessToken": "jwt-access-token",
      "refreshToken": "jwt-refresh-token",
      "expiresIn": 86400
    }
  }
}
```

**Error Response (401 Unauthorized):**
```json
{
  "success": false,
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "Invalid email or password"
  }
}
```

### POST /api/auth/logout
Logout user and invalidate tokens.

**Headers:**
```
Authorization: Bearer <access-token>
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Logout successful"
}
```

### POST /api/auth/refresh
Refresh access token using refresh token.

**Request Body:**
```json
{
  "refreshToken": "jwt-refresh-token"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "data": {
    "accessToken": "new-jwt-access-token",
    "expiresIn": 86400
  }
}
```

### POST /api/auth/forgot-password
Request password reset email.

**Request Body:**
```json
{
  "email": "user@example.com"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Password reset email sent if account exists"
}
```

### POST /api/auth/reset-password
Reset password using reset token.

**Request Body:**
```json
{
  "token": "reset-token-from-email",
  "newPassword": "NewSecurePass123!"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Password reset successful"
}
```

### GET /api/auth/verify-email/:token
Verify email address using verification token.

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Email verified successfully"
}
```

## User Management Endpoints

### GET /api/users/profile
Get current user profile.

**Headers:**
```
Authorization: Bearer <access-token>
```

**Response (200 OK):**
```json
{
  "success": true,
  "data": {
    "id": "uuid-string",
    "email": "user@example.com",
    "firstName": "John",
    "lastName": "Doe",
    "role": "user",
    "emailVerified": true,
    "createdAt": "2024-01-01T00:00:00Z",
    "lastLogin": "2024-01-15T10:30:00Z"
  }
}
```

### PUT /api/users/profile
Update user profile.

**Headers:**
```
Authorization: Bearer <access-token>
```

**Request Body:**
```json
{
  "firstName": "John",
  "lastName": "Smith",
  "avatar": "base64-image-data"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Profile updated successfully",
  "data": {
    "id": "uuid-string",
    "email": "user@example.com",
    "firstName": "John",
    "lastName": "Smith",
    "role": "user"
  }
}
```

### DELETE /api/users/account
Delete user account.

**Headers:**
```
Authorization: Bearer <access-token>
```

**Request Body:**
```json
{
  "password": "current-password-for-confirmation"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Account deleted successfully"
}
```

## Admin Endpoints

### GET /api/admin/users
Get list of all users (admin only).

**Headers:**
```
Authorization: Bearer <admin-access-token>
```

**Query Parameters:**
- `page`: Page number (default: 1)
- `limit`: Items per page (default: 20)
- `search`: Search by email or name
- `role`: Filter by role

**Response (200 OK):**
```json
{
  "success": true,
  "data": {
    "users": [
      {
        "id": "uuid-string",
        "email": "user@example.com",
        "firstName": "John",
        "lastName": "Doe",
        "role": "user",
        "emailVerified": true,
        "createdAt": "2024-01-01T00:00:00Z",
        "lastLogin": "2024-01-15T10:30:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total": 100,
      "pages": 5
    }
  }
}
```

### PUT /api/admin/users/:id
Update user (admin only).

**Headers:**
```
Authorization: Bearer <admin-access-token>
```

**Request Body:**
```json
{
  "firstName": "John",
  "lastName": "Doe", 
  "role": "admin",
  "emailVerified": true
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "User updated successfully",
  "data": {
    "id": "uuid-string",
    "email": "user@example.com",
    "firstName": "John",
    "lastName": "Doe",
    "role": "admin",
    "emailVerified": true
  }
}
```

## Error Responses

### Standard Error Format
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": "Additional error details (optional)"
  }
}
```

### Common Error Codes
- `VALIDATION_ERROR`: Request validation failed
- `INVALID_CREDENTIALS`: Login credentials invalid
- `UNAUTHORIZED`: Authentication required
- `FORBIDDEN`: Insufficient permissions
- `USER_NOT_FOUND`: User does not exist
- `EMAIL_ALREADY_EXISTS`: Email already registered
- `TOKEN_EXPIRED`: JWT token has expired
- `TOKEN_INVALID`: JWT token is invalid
- `RATE_LIMIT_EXCEEDED`: Too many requests
- `INTERNAL_ERROR`: Server error

## Rate Limiting
- Login attempts: 5 per IP per minute
- Registration: 3 per IP per minute
- Password reset: 3 per email per hour
- API calls: 100 per user per minute

## Security Headers
All responses include security headers:
```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'self'
```

## Authentication Flow
1. User registers with email/password
2. Verification email sent with token
3. User clicks verification link
4. User can now login
5. Login returns access token (24h) and refresh token (30d)
6. Access token used for authenticated requests
7. Refresh token used to get new access token when expired
8. Logout invalidates both tokens

## Database Schema References
- Users table: id, email, password_hash, first_name, last_name, role, email_verified, created_at, updated_at, last_login
- Sessions table: id, user_id, token_hash, expires_at, created_at

## Implementation Notes
- Use bcrypt for password hashing (cost factor 12)
- JWT tokens signed with RS256 algorithm
- Email verification tokens expire after 24 hours
- Password reset tokens expire after 1 hour
- Implement proper CORS for frontend domain
- Use HTTPS in production
- Log all authentication events for security monitoring