# Regenerate the checked-in Xcode project using the existing xcodeproj Ruby gem.
require 'xcodeproj'
require 'pathname'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'KeepUp.xcodeproj'))
project.root_object.development_region = 'en'
project.root_object.known_regions = ['en', 'zh-Hans']

app = project.new_target(:application, 'KeepUp', :ios, '26.0')
project.root_object.attributes['TargetAttributes'] = {
  app.uuid => { 'SystemCapabilities' => { 'com.apple.ApplicationGroups.iOS' => { 'enabled' => 1 } } }
}
unit_tests = project.new_target(:unit_test_bundle, 'KeepUpTests', :ios, '26.0')
ui_tests = project.new_target(:ui_test_bundle, 'KeepUpUITests', :ios, '26.0')
unit_tests.add_dependency(app)
ui_tests.add_dependency(app)

wcdb = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
wcdb.repositoryURL = 'https://github.com/Tencent/wcdb.git'
wcdb.requirement = { 'kind' => 'exactVersion', 'version' => '2.1.16' }
project.root_object.package_references << wcdb
[app, unit_tests].each do |target|
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = wcdb
  product.product_name = 'WCDBSwift'
  target.package_product_dependencies << product
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  target.frameworks_build_phase.files << build_file
end

crop = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
crop.repositoryURL = 'https://github.com/TimOliver/TOCropViewController.git'
crop.requirement = { 'kind' => 'exactVersion', 'version' => '3.2.0' }
project.root_object.package_references << crop
crop_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
crop_product.package = crop
crop_product.product_name = 'TOCropViewController'
app.package_product_dependencies << crop_product
crop_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
crop_build_file.product_ref = crop_product
app.frameworks_build_phase.files << crop_build_file

defaults = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
defaults.repositoryURL = 'https://github.com/sindresorhus/Defaults'
defaults.requirement = { 'kind' => 'revision', 'revision' => '00a7465a0668a87fa159e779b9d80f1f9652357e' }
project.root_object.package_references << defaults
[app, unit_tests].each do |target|
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = defaults
  product.product_name = 'Defaults'
  target.package_product_dependencies << product
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  target.frameworks_build_phase.files << build_file
end

alamofire = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
alamofire.repositoryURL = 'https://github.com/Alamofire/Alamofire.git'
alamofire.requirement = { 'kind' => 'exactVersion', 'version' => '5.12.2' }
project.root_object.package_references << alamofire
alamofire_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
alamofire_product.package = alamofire
alamofire_product.product_name = 'Alamofire'
app.package_product_dependencies << alamofire_product
alamofire_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
alamofire_build_file.product_ref = alamofire_product
app.frameworks_build_phase.files << alamofire_build_file

swiftyrsa = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
swiftyrsa.repositoryURL = 'https://github.com/TakeScoop/SwiftyRSA.git'
swiftyrsa.requirement = { 'kind' => 'exactVersion', 'version' => '1.8.0' }
project.root_object.package_references << swiftyrsa
swiftyrsa_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
swiftyrsa_product.package = swiftyrsa
swiftyrsa_product.product_name = 'SwiftyRSA'
app.package_product_dependencies << swiftyrsa_product
swiftyrsa_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
swiftyrsa_build_file.product_ref = swiftyrsa_product
app.frameworks_build_phase.files << swiftyrsa_build_file

def add_directory(group, path, target)
  Dir.children(path).sort.each do |name|
    full = File.join(path, name)
    if File.directory?(full) && !name.end_with?('.xcassets', '.bundle')
      add_directory(group.new_group(name, name), full, target)
    elsif name.end_with?('.swift', '.m')
      target.source_build_phase.add_file_reference(group.new_file(name))
    elsif name.end_with?('.xcassets', '.xcstrings', '.json', '.bundle')
      target.resources_build_phase.add_file_reference(group.new_file(name))
    elsif name.end_with?('.h')
      group.new_file(name)
    end
  end
end

[[app, 'KeepUp'], [unit_tests, 'KeepUpTests'], [ui_tests, 'KeepUpUITests']].each do |target, directory|
  add_directory(project.main_group.new_group(directory, directory), File.join(root, directory), target)
  target.build_configurations.each do |config|
    config.build_settings.merge!(
      'SWIFT_VERSION' => '6.0',
      'SWIFT_STRICT_CONCURRENCY' => 'complete',
      'IPHONEOS_DEPLOYMENT_TARGET' => '26.0',
      'TARGETED_DEVICE_FAMILY' => '1',
      'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
      'SUPPORTS_MACCATALYST' => 'NO',
      'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
      'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
      'CODE_SIGN_STYLE' => 'Automatic',
      'GENERATE_INFOPLIST_FILE' => target == app ? 'NO' : 'YES',
      'PRODUCT_BUNDLE_IDENTIFIER' => target == app ? 'com.bestlife.keepup' : "com.bestlife.keepup.#{target.name}",
      'MARKETING_VERSION' => '1.0.0',
      'CURRENT_PROJECT_VERSION' => '1',
      'SWIFT_EMIT_LOC_STRINGS' => 'NO',
      'STRING_CATALOG_GENERATE_SYMBOLS' => 'NO'
    )
  end
end
app.build_configurations.each do |config|
  config.build_settings.delete('ASSETCATALOG_COMPILER_APPICON_NAME')
  config.build_settings['INFOPLIST_FILE'] = 'Config/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/KeepUp.entitlements'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
end
unit_tests.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/KeepUp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/KeepUp'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
ui_tests.build_configurations.each { |config| config.build_settings['TEST_TARGET_NAME'] = 'KeepUp' }
config_group = project.main_group.new_group('Config', 'Config')
config_group.new_file('Info.plist')
config_group.new_file('KeepUp.entitlements')
privacy_strings = config_group.new_variant_group('InfoPlist.strings')
['en', 'zh-Hans'].each do |locale|
  file = privacy_strings.new_file("#{locale}.lproj/InfoPlist.strings")
  file.name = locale
end
app.resources_build_phase.add_file_reference(privacy_strings)
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(unit_tests)
scheme.add_test_target(ui_tests)
scheme.save_as(project.path, 'KeepUp')
puts "Generated #{project.path}"
