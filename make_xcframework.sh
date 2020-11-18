xcodebuild -create-xcframework \
 -library openssl/openssl-ios-x86_64-maccatalyst.a -headers openssl/Catalyst/include \
 -library openssl/openssl-ios-armv7_arm64.a -headers openssl/iOS/include \
 -library openssl/openssl-ios-x86_64-simulator.a -headers openssl/iOS-simulator/include \
  -output openssl.xcframework

xcodebuild -create-xcframework \
 -library curl/lib/libcurl_Catalyst.a -headers curl/include \
 -library curl/lib/libcurl_iOS.a -headers curl/include \
 -library curl/lib/libcurl_iOS-simulator.a -headers curl/include \
  -output curl.xcframework
