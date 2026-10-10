#!/usr/bin/env ruby
# Deterministic Xcode project; no gems or generated user-specific signing identity.
require 'digest'
require 'fileutils'
Dir.chdir(File.expand_path('..', __dir__))
def id(name)
  Digest::SHA256.hexdigest(name)[0, 24].upcase
end
def q(value)
  '"' + value.to_s.gsub('"', '\\"') + '"'
end
objects = {}
put = ->(name, body) { objects[id(name)] = body; id(name) }
files = Dir['Sources/CliporiIOS/*.swift'].sort + ['Sources/CliporiMac/Design.swift']
mac_files = Dir['Sources/CliporiMac/*.swift'].sort
all_files = (files + mac_files).uniq
all_files.each { |p| put.call(p, "isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{q(p)}; sourceTree = SOURCE_ROOT;") }
resources = ['Resources/Assets.xcassets', 'Resources/AppIcon.icns']
resources.each { |p| put.call(p, "isa = PBXFileReference; lastKnownFileType = #{p.end_with?('xcassets') ? 'folder.assetcatalog' : 'image.icns'}; path = #{q(p)}; sourceTree = SOURCE_ROOT;") }
product_ids = []; target_ids = []
package_id = put.call('package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
['iOS', 'Mac'].each do |platform|
  target = platform == 'iOS' ? 'CliporiIOS' : 'CliporiMac'
  source_paths = platform == 'iOS' ? files : mac_files
  product = put.call("#{target}-product", "isa = PBXFileReference; explicitFileType = wrapper.application; path = Clipori.app; sourceTree = BUILT_PRODUCTS_DIR;")
  product_ids << product
  dependency = put.call("#{target}-core", "isa = XCSwiftPackageProductDependency; package = #{package_id}; productName = CliporiCore;")
  library_build = put.call("#{target}-library", "isa = PBXBuildFile; productRef = #{dependency};")
  builds = source_paths.map { |p| put.call("#{target}:#{p}", "isa = PBXBuildFile; fileRef = #{id(p)};") }
  sources = put.call("#{target}-sources", "isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (#{builds.join(',')}); runOnlyForDeploymentPostprocessing = 0;")
  frameworks = put.call("#{target}-frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (#{library_build}); runOnlyForDeploymentPostprocessing = 0;")
  resource = platform == 'iOS' ? resources[0] : resources[1]
  resource_build = put.call("#{target}-resource", "isa = PBXBuildFile; fileRef = #{id(resource)};")
  resource_phase = put.call("#{target}-resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (#{resource_build}); runOnlyForDeploymentPostprocessing = 0;")
  configs = ['Debug', 'Release'].map do |config|
    settings = { 'PRODUCT_NAME' => 'Clipori', 'PRODUCT_BUNDLE_IDENTIFIER' => platform == 'iOS' ? 'app.clipori.ios' : 'app.clipori', 'SWIFT_VERSION' => '5.0', 'CODE_SIGN_STYLE' => 'Automatic', 'GENERATE_INFOPLIST_FILE' => 'NO', 'CLIPORI_CLOUD_CONTAINER' => '', 'SWIFT_OPTIMIZATION_LEVEL' => config == 'Debug' ? '-Onone' : '-O', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES' }
    settings['ONLY_ACTIVE_ARCH'] = config == 'Debug' ? 'YES' : 'NO'
    if platform == 'iOS'
      settings.merge!('SDKROOT' => 'iphoneos', 'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator', 'IPHONEOS_DEPLOYMENT_TARGET' => '17.0', 'TARGETED_DEVICE_FAMILY' => '1,2', 'INFOPLIST_FILE' => 'Resources/iOS-Info.plist', 'SUPPORTS_MACCATALYST' => 'NO', 'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon')
    else
      settings.merge!('SDKROOT' => 'macosx', 'MACOSX_DEPLOYMENT_TARGET' => '14.0', 'INFOPLIST_FILE' => 'Resources/Mac-Xcode-Info.plist', 'ENABLE_HARDENED_RUNTIME' => 'YES')
    end
    put.call("#{target}-#{config}", "isa = XCBuildConfiguration; name = #{config}; buildSettings = { #{settings.map { |k,v| "#{k} = #{q(v)};" }.join(' ')} };")
  end
  list = put.call("#{target}-configs", "isa = XCConfigurationList; buildConfigurations = (#{configs.join(',')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
  target_id = put.call(target, "isa = PBXNativeTarget; name = #{target}; productName = Clipori; productType = \"com.apple.product-type.application\"; productReference = #{product}; buildConfigurationList = #{list}; buildPhases = (#{sources},#{frameworks},#{resource_phase}); buildRules = (); dependencies = (); packageProductDependencies = (#{dependency});")
  target_ids << target_id
  dir = 'Clipori.xcodeproj/xcshareddata/xcschemes'; FileUtils.mkdir_p(dir)
  File.write("#{dir}/#{target}.xcscheme", <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme LastUpgradeVersion="1640" version="1.3">
      <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{target_id}" BuildableName="Clipori.app" BlueprintName="#{target}" ReferencedContainer="container:Clipori.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
      <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{target_id}" BuildableName="Clipori.app" BlueprintName="#{target}" ReferencedContainer="container:Clipori.xcodeproj"/></BuildableProductRunnable></LaunchAction>
      <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
      <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
    </Scheme>
  XML
end
products = put.call('products', "isa = PBXGroup; name = Products; children = (#{product_ids.join(',')}); sourceTree = \"<group>\";")
main = put.call('main', "isa = PBXGroup; children = (#{((all_files + resources).map { |p| id(p) } + [products]).join(',')}); sourceTree = \"<group>\";")
configs = ['Debug', 'Release'].map { |c| put.call("project-#{c}", "isa = XCBuildConfiguration; name = #{c}; buildSettings = { CLANG_ENABLE_MODULES = YES; };" ) }
list = put.call('project-configs', "isa = XCConfigurationList; buildConfigurations = (#{configs.join(',')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
root = put.call('project', "isa = PBXProject; attributes = { LastUpgradeCheck = 1640; }; buildConfigurationList = #{list}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; knownRegions = (\"zh-Hans\",en,Base); mainGroup = #{main}; productRefGroup = #{products}; projectDirPath = \"\"; projectRoot = \"\"; packageReferences = (#{package_id}); targets = (#{target_ids.join(',')});")
File.write('Clipori.xcodeproj/project.pbxproj', "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + objects.map { |key, value| "#{key} = { #{value} };" }.join("\n") + "\n}; rootObject = #{root}; }\n")
