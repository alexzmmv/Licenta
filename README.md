# GJournal Native iOS App with Backend Integration

SwiftUI emotion journaling app with FastAPI backend, JWT authentication, and biometric/passcode security.

## Features

### Authentication
- User registration and login
- JWT token-based authentication
- Secure token storage in UserDefaults
- Auto-login with saved credentials

### Biometric Security
- Face ID / Touch ID authentication
- Passcode fallback
- Banking-app style lock screen
- Enable/disable in settings

### Journal Functionality
- Create, read, update, delete journal entries ("bits")
- 12 emotions with emojis and colors
- Intensity levels (1-4)
- Calendar view with bit indicators
- Top emotions statistics
- Hide/show entries

## Architecture

### Backend API
- **FastAPI** with PostgreSQL
- JWT authentication (30-day tokens)
- RESTful CRUD endpoints
- Docker Compose deployment

### iOS App Structure
```
GJournal/
├── Models/
│   ├── Emotion.swift          # Emotion enum with colors/emojis
│   └── Bit.swift              # Journal entry model
├── Repository/
│   ├── APIClient.swift        # HTTP client for backend
│   ├── AuthManager.swift      # Auth + biometric manager
│   ├── JournalAPIRepository.swift  # API-backed data layer
│   └── [Other repositories...]
├── Views/
│   ├── LoginView.swift        # Login screen
│   ├── RegisterView.swift     # Registration screen
│   ├── BiometricLockView.swift # Biometric auth screen
│   ├── SettingsView.swift     # Account & security settings
│   ├── ContentView.swift      # Main home screen
│   ├── DayDetailView.swift    # Day's bits list
│   ├── AddEditBitView.swift   # Create/edit bit
│   ├── BitCard.swift          # Bit display card
│   ├── CalendarView.swift     # Month calendar
│   └── TopEmotionsView.swift  # Statistics
└── GJournalApp.swift          # App entry point
```

## Setup

### 1. Backend Setup

Start the FastAPI backend and PostgreSQL:

```bash
cd backend
docker-compose up --build
```

The API will be available at `http://localhost:8000`

**API Documentation:**
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### 2. iOS App Setup

#### Requirements
- Xcode 15.0+
- iOS 16.0+ device/simulator
- Backend running on localhost:8000

#### Configure API URL

In `APIClient.swift`, update the `baseURL` if needed:
```swift
private let baseURL = "http://localhost:8000"  // Change for production
```

For iOS Simulator, use:
- `http://localhost:8000` works directly
- For physical device on same network: `http://YOUR_MAC_IP:8000`

#### Add Face ID Permission

**Important:** Add this key to your `Info.plist` for Face ID to work:

```xml
<key>NSFaceIDUsageDescription</key>
<string>GJournal uses Face ID to securely unlock the app and protect your emotional journal entries.</string>
```

In Xcode:
1. Select your project in the navigator
2. Select the GJournal target
3. Go to Info tab
4. Add "Privacy - Face ID Usage Description" with the above message

#### Build and Run

1. Open `GJournal.xcodeproj` in Xcode
2. Select your target device/simulator
3. Build and run (⌘+R)

## Usage Flow

### First Time Setup

1. **Launch App** → Shows login screen
2. **Tap "Sign up"** → Register with email/password
3. **Auto-login** → Redirected to main app
4. **Optional:** Go to Settings (gear icon) → Enable biometric authentication

### Daily Use

1. **App Launch** → Biometric unlock (if enabled)
2. **Home Screen:**
   - View calendar with bit indicators
   - See top 3 emotions from last 30 days
   - Tap `+` to create new bit (only for today)
3. **Tap a date** → View/edit bits for that day
4. **Create Bit:**
   - Optional title
   - Write your thoughts
   - Select emotion
   - Choose intensity (1-4)
5. **Manage Bits:**
   - Edit (today/yesterday only)
   - Hide/unhide
   - Delete

### Settings

- **Account:** View current email
- **Security:** Toggle biometric/passcode lock
- **Log Out:** Clear credentials and return to login

## API Endpoints

### Authentication
- `POST /auth/register` - Register new user
- `POST /auth/login` - Login, receive JWT token

### Bits (Requires Bearer Token)
- `GET /bits/` - Get all user's bits
- `POST /bits/` - Create new bit
- `GET /bits/{id}` - Get specific bit
- `PUT /bits/{id}` - Update bit
- `DELETE /bits/{id}` - Delete bit
- `PATCH /bits/{id}/toggle-hide` - Toggle visibility

## Data Models

### Emotion
12 emotions with visual representation:
- Joy 😊, Sadness 😢, Anger 😠, Fear 😰
- Love ❤️, Surprise 😲, Disgust 🤢, Anxiety 😟
- Excitement 🤩, Gratitude 🙏, Hope 🌟, Guilt 😔

### Bit (Journal Entry)
```swift
struct Bit {
    let id: UUID
    var title: String?        // Optional
    var text: String          // Required
    var emotion: Emotion      // One of 12 emotions
    var intensity: Int        // 1-4 scale
    var isHidden: Bool        // Visibility
    let createdAt: Date
    var lastModified: Date
}
```

### API Response Format
```json
{
  "id": 1,
  "title": "Great day!",
  "text": "Had an amazing time...",
  "emotion": "joy",
  "intensity": 4,
  "is_hidden": false,
  "created_at": "2025-11-14T10:30:00",
  "last_modified": "2025-11-14T10:30:00",
  "user_id": 1
}
```

## Security Features

### Authentication
- Passwords hashed with bcrypt
- JWT tokens with 30-day expiration
- Tokens stored securely in UserDefaults
- Auto-refresh on app launch

### Biometric Lock
- Face ID / Touch ID on supported devices
- Automatic passcode fallback
- Re-authentication on app launch
- Can be disabled in settings

### API Security
- All bit endpoints require authentication
- User can only access their own data
- CORS configured for API access

## Development Notes

### ID Mapping
The API uses integer IDs while the iOS app uses UUIDs. For this demo:
- Bits are fetched from API on load
- Locally managed with UUID
- Full CRUD requires ID mapping layer (TODO for production)

### Local vs. API Repository
- `JournalAPIRepository` - Connects to backend
- `JournalInMemoRepository` - In-memory for testing
- `JournalCoreDataRepository` - Local persistence option

Switch repositories in `GJournalApp.swift` or `BiometricLockView.swift`.

### Testing Without Backend
To test UI without backend running:
1. Comment out API repository in `BiometricLockView.swift`
2. Use `JournalInMemoRepository()` instead
3. Comment out authentication flow in `GJournalApp.swift`

## Production Checklist

### Backend
- [ ] Change `SECRET_KEY` to secure random string
- [ ] Update CORS origins to specific domains
- [ ] Use environment-specific `.env` files
- [ ] Set up HTTPS/SSL
- [ ] Configure proper PostgreSQL backup
- [ ] Add rate limiting
- [ ] Set up logging/monitoring

### iOS App
- [ ] Update API base URL for production
- [ ] Implement proper ID mapping for API entities
- [ ] Add Keychain storage for sensitive data
- [ ] Implement token refresh mechanism
- [ ] Add offline mode with local caching
- [ ] Handle network errors gracefully
- [ ] Add loading states and retry logic
- [ ] Implement proper error tracking
- [ ] Test on physical devices with Face ID

## Troubleshooting

### "Not authenticated" errors
- Backend not running
- Token expired (restart app to re-login)
- Check API URL in `APIClient.swift`

### Face ID not working
- Check `Info.plist` has Face ID permission
- Device/simulator must support biometric authentication
- Enable in Settings first

### Cannot connect to API
- Ensure backend is running: `docker-compose up`
- Check firewall settings
- For physical device: Use Mac's local IP, not localhost
- Verify network connectivity

### Build errors in Xcode
- Clean build folder (⇧⌘K)
- Ensure iOS deployment target matches
- Check all new files are added to target

## License

MIT License - Feel free to use for learning and projects.

## Contributing

1. Backend changes: Test with `docker-compose up --build`
2. iOS changes: Ensure backward compatibility
3. Update this README for new features
4. Test authentication flow thoroughly
