# FreeAPS X Project Rules and Guidelines

## Core Project Information
- **Project Type**: iOS Xcode project for diabetes management (artificial pancreas system)
- **Language**: Swift
- **Architecture**: MVVM with Combine framework
- **Dependency Injection**: Swinject
- **Key Framework**: LoopKit for diabetes device integration
- **Algorithm**: OpenAPS oref0 (original JavaScript implementation)

## Critical Development Rules

### 1. Xcode Project Management
- **ALWAYS use Ruby scripts** for adding files to Xcode project, NOT Python
- **Clean FreeAPS derived data only**: `rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*`
- **Notify user** when new source files are added so they can manually integrate them
- **Compile after each code modification** until successful compilation

### 2. Configuration Management
- **Use ConfigOverride.xcconfig** for all app settings instead of hardcoding in Info.plist:
  - APP_DISPLAY_NAME
  - APP_VERSION  
  - APP_BUILD_NUMBER
  - DEVELOPER_TEAM
  - BUNDLE_IDENTIFIER
  - APP_GROUP_ID
- **OpenAPS Algorithm**: Uses original oref0 JavaScript files for stability

### 3. Logging and Notifications
- **Write notifications ONLY to notifications.txt**, not to log files
- **Maintain max 1000 entries** in notifications.txt by removing older entries
- **Use os_log** for detailed diagnostics and tracing execution flow
- **Event names should include timestamps** (without seconds)

### 4. Nightscout Integration Best Practices
- **Direct API testing is preferred** over queue-based testing for connection verification
- **EnhancedNightscoutQueueManager has cooldowns** - tasks like .treatments have 45-second cooldown
- **Queue tasks are processed asynchronously** by background tasker
- **Use nightscoutAPI.checkConnection()** for immediate connection testing
- **API secret must be SHA1 hashed** and sent in `api-secret` header (not as token)
- **Keychain storage** for URL and API secret with proper error handling

### 5. Dependency Injection Patterns
- **Use @Injected() property wrapper** for dependency injection
- **Handle optional dependencies safely** with guard let checks
- **Avoid implicitly unwrapped optionals** (!) - use optional types (?) instead
- **Always check for nil** before using injected services

### 6. Error Handling
- **Implement robust error handling** for network and Keychain operations
- **Use guard let statements** for safe optional unwrapping
- **Provide meaningful error messages** to users
- **Handle dependency resolution failures** gracefully

### 7. Network and Security
- **Use URLSession.shared.dataTaskPublisher** with Combine for async operations
- **Implement proper timeout handling** for network requests
- **Secure storage** of sensitive data in Keychain
- **SHA1 hashing** for API secrets before transmission

### 8. Memory Management
- **Use weak self** in closures to prevent retain cycles
- **Proper cleanup** of Combine subscriptions
- **Monitor memory usage** in development

### 9. Code Quality
- **Follow Swift naming conventions**
- **Use meaningful variable names**
- **Add comments for complex logic**
- **Keep methods focused and small**

### 10. Testing and Debugging
- **Test on iPhone 16 simulator** (not iPhone 15)
- **Use proper build destinations** for iOS Simulator
- **Monitor console logs** for debugging
- **Test edge cases** and error conditions

## Common Issues and Solutions

### Compilation Errors
- **"Cannot convert value of type"**: Check type annotations in closures
- **"Cannot infer type"**: Add explicit type annotations
- **"Unexpectedly found nil"**: Add guard let checks for optionals

### Runtime Issues
- **Fatal errors with optionals**: Convert ! to ? and add proper nil checks
- **Network timeouts**: Implement proper timeout handling
- **Keychain access failures**: Check entitlements and permissions

### Performance Issues
- **Memory leaks**: Use weak references in closures
- **Slow network**: Implement proper caching and retry logic
- **UI freezes**: Move heavy operations to background queues

## Project Structure
- **FreeAPS/Sources/**: Main application source code
- **Dependencies/**: Third-party libraries and frameworks
- **FreeAPS.xcodeproj/**: Xcode project file
- **Config.xcconfig**: Configuration files
- **Templates/**: Code templates for new files

## Key Files and Their Purposes
- **OpenAPS.swift**: Core oref0 algorithm implementation
- **APSManager.swift**: Main APS loop management
- **NightscoutConfigStateModel.swift**: Manages Nightscout configuration and connection
- **NightscoutAPI.swift**: Handles direct API communication with Nightscout
- **EnhancedNightscoutQueueManager.swift**: Manages upload queue with priorities and retries
- **NetworkService.swift**: Generic network service layer
- **Keychain.swift**: Secure storage implementation

## Project Architecture

### 1. Client-Side Architecture (iOS App)
- **MVVM Pattern**: Model-View-ViewModel with Combine framework
- **Dependency Injection**: Swinject container for service management
- **Service Layer**: 
  - `OpenAPS`: Core oref0 algorithm execution
  - `APSManager`: Main loop management
  - `NightscoutManager`: Handles Nightscout integration
- **Data Persistence**: 
  - Keychain for sensitive data (API keys, user tokens)
  - File storage for glucose and treatment data
  - UserDefaults for app settings
- **UI Layer**: SwiftUI views with Combine publishers for reactive updates

### 2. OpenAPS Integration
- **Algorithm**: Original oref0 JavaScript files
- **JavaScript Worker**: Executes oref0 algorithms in background
- **Data Flow**: CGM → OpenAPS → Pump commands
- **Safety**: Built-in safety checks and limits from oref0

### 3. Data Flow Architecture
- **Glucose Data**: CGM → FreeAPS → OpenAPS → Pump
- **Settings Sync**: App ↔ Nightscout via API
- **Notifications**: System state and device status
- **Hybrid Mode**: Local processing with cloud backup

## Development Workflow
1. **Make code changes**
2. **Compile immediately** to catch errors
3. **Test functionality** thoroughly
4. **Notify user** of any new files added
5. **Document changes** in commit messages

## Security Considerations
- **Never hardcode sensitive data**
- **Use Keychain for secrets**
- **Hash API secrets** before transmission
- **Validate user inputs**
- **Implement proper error handling**

## Performance Guidelines
- **Use background queues** for heavy operations
- **Implement proper caching**
- **Monitor memory usage**
- **Optimize network requests**
- **Use Combine for reactive programming**

## Testing Strategy
- **Unit tests** for business logic
- **Integration tests** for API communication
- **UI tests** for user interactions
- **Performance tests** for critical paths
- **Security tests** for data protection

## Documentation Standards
- **Comment complex algorithms**
- **Document API interfaces**
- **Explain configuration options**
- **Provide usage examples**
- **Keep README files updated**

## Deployment Considerations
- **Test on multiple devices**
- **Verify all configurations**
- **Check app permissions**
- **Validate network connectivity**
- **Test error scenarios**

## Maintenance
- **Regular dependency updates**
- **Code review process**
- **Performance monitoring**
- **Security audits**
- **User feedback integration**

## Swift Package Manager Issues
- **After using Ruby scripts, ALWAYS run**: `./fix_package_dependencies.sh`
- **Common errors**: Missing package product 'SwiftCharts', 'Swinject', 'SwiftDate', 'SlideButton', 'SwiftMessages', 'Algorithms', 'CryptoSwift'
- **Manual fix**: `xcodebuild -resolvePackageDependencies` then clean derived data
- **Prevention**: Use `ruby_script_template.rb` for new Ruby scripts
- **Emergency recovery**: Close Xcode, run fix script, reopen Xcode, clean build folder

## Emergency Procedures
- **Rollback to previous version** if critical issues arise
- **Disable problematic features** temporarily
- **Contact development team** for urgent issues
- **Document incident response** procedures

## Future Considerations
- **Plan for iOS updates**
- **Monitor framework changes**
- **Stay updated with LoopKit**
- **Consider user feedback**
- **Plan for scalability**

---

*Last updated: 2025-01-27*
*Adapted from iaps project rules for FreeAPS X with oref0 focus*
