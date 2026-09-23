#!/usr/bin/env python3
"""
Generates project.pbxproj for the Aliaro iOS app from the current contents
of the Aliaro/, AliaroShared/ and AliaroWidgets/ source folders. Re-run
after adding/removing files in any of them.

Classic (non file-system-synchronized) PBXFileReference/PBXGroup format,
compatible with Xcode 14+. Two targets:
  - "Aliaro": the app (iOS 17, SwiftUI lifecycle, no physical Info.plist).
  - "AliaroWidgetsExtension": the WidgetKit extension (physical Info.plist,
    since it needs the NSExtension dict that GENERATE_INFOPLIST_FILE can't
    express), embedded into the app and sharing an App Group with it.
AliaroShared/ files are compiled into BOTH targets (plain Codable models +
the App Group read/write helper — the bridge between app and widget).
"""
import os
import re
import uuid
import json

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "Aliaro")
SHARED_SRC = os.path.join(ROOT, "AliaroShared")
WIDGET_SRC = os.path.join(ROOT, "AliaroWidgets")
PROJ_DIR = os.path.join(ROOT, "Aliaro.xcodeproj")

BUNDLE_ID = "com.devaro.aliaro"
BUNDLE_ID_DEV = "com.devaro.aliaro.dev"  # Debug: bundle id distinto para instalar junto a la de produccion
WIDGET_BUNDLE_ID = "com.devaro.aliaro.widgets"
WIDGET_BUNDLE_ID_DEV = "com.devaro.aliaro.dev.widgets"
APP_GROUP_ID = "group.com.devaro.aliaro"
APP_GROUP_ID_DEV = "group.com.devaro.aliaro.dev"

PRODUCT_NAME = "Aliaro"
WIDGET_PRODUCT_NAME = "AliaroWidgetsExtension"
DEPLOYMENT_TARGET = "17.0"

# Preserve DEVELOPMENT_TEAM / CURRENT_PROJECT_VERSION / MARKETING_VERSION across
# regenerations: read them from the existing project.pbxproj (if any) before
# it gets overwritten, since this script rewrites the file from scratch.
DEVELOPMENT_TEAM = ""
CURRENT_PROJECT_VERSION = "1"
MARKETING_VERSION = "1.0"
_existing_pbxproj = os.path.join(PROJ_DIR, "project.pbxproj")
if os.path.exists(_existing_pbxproj):
    with open(_existing_pbxproj) as f:
        _old = f.read()
    _m = re.search(r'DEVELOPMENT_TEAM = (\S+?);', _old)
    if _m:
        DEVELOPMENT_TEAM = _m.group(1)
    _m = re.search(r'CURRENT_PROJECT_VERSION = (\S+?);', _old)
    if _m:
        CURRENT_PROJECT_VERSION = _m.group(1)
    _m = re.search(r'MARKETING_VERSION = (\S+?);', _old)
    if _m:
        MARKETING_VERSION = _m.group(1)
DEVELOPMENT_TEAM_LINE = f"\t\t\t\tDEVELOPMENT_TEAM = {DEVELOPMENT_TEAM};\n" if DEVELOPMENT_TEAM else ""

_SAFE_UNQUOTED = re.compile(r'^[A-Za-z0-9_./]+$')
def q(s):
    """Quote a plist string if it contains characters unsafe as a bare token (Xcode's own writer does this too)."""
    if _SAFE_UNQUOTED.match(s):
        return s
    escaped = s.replace(chr(92), chr(92)*2).replace('"', chr(92) + '"')
    return '"' + escaped + '"'

_ids = {}
_cache_path = os.path.join(ROOT, ".pbx_uid_cache.json")
if os.path.exists(_cache_path):
    with open(_cache_path) as f:
        _ids = json.load(f)
def uid(key):
    if key not in _ids:
        _ids[key] = uuid.uuid4().hex[:24].upper()
    return _ids[key]

def collect(dirpath):
    """Return (files, subdirs) with relative-to-SRC-parent paths, sorted."""
    entries = sorted(os.listdir(dirpath))
    files, dirs = [], []
    for e in entries:
        if e.startswith('.'):
            continue
        full = os.path.join(dirpath, e)
        if e.endswith('.xcassets'):
            files.append(e)
        elif os.path.isdir(full):
            dirs.append(e)
        elif e.endswith('.swift'):
            files.append(e)
        elif e.endswith('.strings'):
            files.append(e)
        elif e.endswith('.xcstrings'):
            files.append(e)
        elif e.endswith('.entitlements'):
            files.append(e)
        elif e.endswith('.storekit'):
            files.append(e)
        elif e.endswith('.plist'):
            files.append(e)
    return files, dirs

file_refs = []       # (uid, name, path, lastKnownFileType, sourceTree)
# Keyed by target key ("app" / "widget"): PBXBuildFile entries for that target's build phases.
build_files = {"app": [], "widget": []}          # Sources phase (.swift only)
resource_build_files = {"app": [], "widget": []}  # Resources phase (.xcassets etc.)
groups = {}           # path -> (uid, name, children uids)

def walk(dirpath, targets):
    """targets: list of target keys ('app', 'widget') whose Sources/Resources
    build phases compiled/copied files under this directory should join."""
    files, dirs = collect(dirpath)
    children = []
    for f in files:
        full = os.path.join(dirpath, f)
        rel_name = f
        fref = uid("fref:" + full)
        if f.endswith('.swift'):
            file_refs.append((fref, rel_name, q(rel_name), "sourcecode.swift", "<group>"))
            for t in targets:
                bf = uid(f"bf:{t}:" + full)
                build_files[t].append((bf, fref, rel_name))
        elif f.endswith('.xcassets'):
            file_refs.append((fref, rel_name, q(rel_name), "folder.assetcatalog", "<group>"))
            for t in targets:
                bf = uid(f"res:{t}:" + full)
                resource_build_files[t].append((bf, fref, rel_name))
        elif f.endswith('.strings'):
            file_refs.append((fref, rel_name, q(rel_name), "text.plist.strings", "<group>"))
            for t in targets:
                bf = uid(f"res:{t}:" + full)
                resource_build_files[t].append((bf, fref, rel_name))
        elif f.endswith('.xcstrings'):
            file_refs.append((fref, rel_name, q(rel_name), "text.json.xcstrings", "<group>"))
            for t in targets:
                bf = uid(f"res:{t}:" + full)
                resource_build_files[t].append((bf, fref, rel_name))
        elif f.endswith('.entitlements'):
            file_refs.append((fref, rel_name, q(rel_name), "text.plist.entitlements", "<group>"))
        elif f.startswith('GoogleService-Info') and f.endswith('.plist'):
            # Firebase config: read at runtime from the bundle (see
            # Core/Analytics.swift), so it must be copied as a resource.
            file_refs.append((fref, rel_name, q(rel_name), "text.plist.xml", "<group>"))
            for t in targets:
                bf = uid(f"res:{t}:" + full)
                resource_build_files[t].append((bf, fref, rel_name))
        elif f.endswith('.plist'):
            # Consumed via INFOPLIST_FILE directly, never through a build
            # phase (that would produce a duplicate-output build error).
            file_refs.append((fref, rel_name, q(rel_name), "text.plist.xml", "<group>"))
        elif f.endswith('.storekit'):
            # Not a build resource (not compiled/copied) — just needs to be
            # visible in the project so Xcode's scheme editor (Run > Options
            # > StoreKit Configuration) can find it.
            file_refs.append((fref, rel_name, q(rel_name), "text", "<group>"))
        children.append(fref)
    for d in dirs:
        full = os.path.join(dirpath, d)
        gkey = full
        gid = uid("grp:" + full)
        child_ids = walk(full, targets)
        groups[gkey] = (gid, d, child_ids)
        children.append(gid)
    return children

app_top_children = walk(SRC, ["app"])
groups[SRC] = (uid("grp:" + SRC), "Aliaro", app_top_children)

shared_top_children = walk(SHARED_SRC, ["app", "widget"])
groups[SHARED_SRC] = (uid("grp:" + SHARED_SRC), "AliaroShared", shared_top_children)

widget_top_children = walk(WIDGET_SRC, ["widget"])
groups[WIDGET_SRC] = (uid("grp:" + WIDGET_SRC), "AliaroWidgets", widget_top_children)

def emit_groups():
    out = []
    for path, (gid, name, child_ids) in groups.items():
        kids = ",\n\t\t\t\t".join(child_ids)
        out.append(f"""\t\t{gid} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{kids}
\t\t\t);
\t\t\tpath = {q(name)};
\t\t\tsourceTree = "<group>";
\t\t}};""")
    return "\n".join(out)

def emit_file_refs():
    out = []
    for fref, name, path, ftype, tree in file_refs:
        quoted_tree = f'"{tree}"' if tree == "<group>" else tree
        out.append(f'\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {path}; sourceTree = {quoted_tree}; }};')
    return "\n".join(out)

def emit_build_files_sources(target):
    out = []
    for bf, fref, name in build_files[target]:
        out.append(f'\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};')
    return "\n".join(out)

def emit_build_files_resources(target):
    out = []
    for bf, fref, name in resource_build_files[target]:
        out.append(f'\t\t{bf} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};')
    return "\n".join(out)

def emit_sources_phase(target):
    out = []
    for bf, fref, name in build_files[target]:
        out.append(f'\t\t\t\t{bf} /* {name} in Sources */,')
    return "\n".join(out)

def emit_resources_phase(target):
    out = []
    for bf, fref, name in resource_build_files[target]:
        out.append(f'\t\t\t\t{bf} /* {name} in Resources */,')
    return "\n".join(out)

PROJECT_UID = uid("project")
MAIN_GROUP = groups[SRC][0]
SHARED_GROUP = groups[SHARED_SRC][0]
WIDGET_GROUP = groups[WIDGET_SRC][0]
PRODUCTS_GROUP = uid("productsGroup")
APP_PRODUCT_REF = uid("appProductRef")
WIDGET_PRODUCT_REF = uid("widgetProductRef")
TARGET_UID = uid("target")
WIDGET_TARGET_UID = uid("widgetTarget")
CONFIGLIST_PROJECT = uid("configListProject")
CONFIGLIST_TARGET = uid("configListTarget")
WIDGET_CONFIGLIST_TARGET = uid("widgetConfigListTarget")
DEBUG_PROJECT_CFG = uid("debugProjectCfg")
RELEASE_PROJECT_CFG = uid("releaseProjectCfg")
DEBUG_TARGET_CFG = uid("debugTargetCfg")
RELEASE_TARGET_CFG = uid("releaseTargetCfg")
WIDGET_DEBUG_TARGET_CFG = uid("widgetDebugTargetCfg")
WIDGET_RELEASE_TARGET_CFG = uid("widgetReleaseTargetCfg")
SOURCES_PHASE = uid("sourcesPhase")
RESOURCES_PHASE = uid("resourcesPhase")
FRAMEWORKS_PHASE = uid("frameworksPhase")
WIDGET_SOURCES_PHASE = uid("widgetSourcesPhase")
WIDGET_RESOURCES_PHASE = uid("widgetResourcesPhase")
WIDGET_FRAMEWORKS_PHASE = uid("widgetFrameworksPhase")
EMBED_EXTENSIONS_PHASE = uid("embedExtensionsPhase")
EMBED_WIDGET_BUILDFILE = uid("embedWidgetBuildFile")
CONTAINER_PROXY_UID = uid("containerProxy")
TARGET_DEPENDENCY_UID = uid("targetDependency")
ROOT_GROUP = uid("rootGroup")
PKG_REF_UID = uid("pkgRef:supabase-swift")
PKG_PRODUCT_UID = uid("pkgProduct:Supabase")
PKG_BUILDFILE_UID = uid("pkgBuildFile:Supabase")
FIREBASE_PKG_REF_UID = uid("pkgRef:firebase-ios-sdk")
FIREBASE_PRODUCT_UID = uid("pkgProduct:FirebaseAnalytics")
FIREBASE_BUILDFILE_UID = uid("pkgBuildFile:FirebaseAnalytics")

pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{emit_build_files_sources("app")}
{emit_build_files_resources("app")}
{emit_build_files_sources("widget")}
{emit_build_files_resources("widget")}
\t\t{PKG_BUILDFILE_UID} /* Supabase in Frameworks */ = {{isa = PBXBuildFile; productRef = {PKG_PRODUCT_UID} /* Supabase */; }};
\t\t{FIREBASE_BUILDFILE_UID} /* FirebaseAnalytics in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIREBASE_PRODUCT_UID} /* FirebaseAnalytics */; }};
\t\t{EMBED_WIDGET_BUILDFILE} /* {WIDGET_PRODUCT_NAME}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {WIDGET_PRODUCT_REF} /* {WIDGET_PRODUCT_NAME}.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{CONTAINER_PROXY_UID} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROJECT_UID} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {WIDGET_TARGET_UID};
\t\t\tremoteInfo = {WIDGET_PRODUCT_NAME};
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{EMBED_EXTENSIONS_PHASE} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{EMBED_WIDGET_BUILDFILE} /* {WIDGET_PRODUCT_NAME}.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
{emit_file_refs()}
\t\t{APP_PRODUCT_REF} /* {PRODUCT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PRODUCT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{WIDGET_PRODUCT_REF} /* {WIDGET_PRODUCT_NAME}.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = {WIDGET_PRODUCT_NAME}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{PKG_BUILDFILE_UID} /* Supabase in Frameworks */,
\t\t\t\t{FIREBASE_BUILDFILE_UID} /* FirebaseAnalytics in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{WIDGET_FRAMEWORKS_PHASE} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{ROOT_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{MAIN_GROUP} /* Aliaro */,
\t\t\t\t{SHARED_GROUP} /* AliaroShared */,
\t\t\t\t{WIDGET_GROUP} /* AliaroWidgets */,
\t\t\t\t{PRODUCTS_GROUP} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{PRODUCTS_GROUP} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{APP_PRODUCT_REF} /* {PRODUCT_NAME}.app */,
\t\t\t\t{WIDGET_PRODUCT_REF} /* {WIDGET_PRODUCT_NAME}.appex */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
{emit_groups()}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET_UID} /* {PRODUCT_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {CONFIGLIST_TARGET} /* Build configuration list for PBXNativeTarget "{PRODUCT_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE} /* Sources */,
\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,
\t\t\t\t{RESOURCES_PHASE} /* Resources */,
\t\t\t\t{EMBED_EXTENSIONS_PHASE} /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{TARGET_DEPENDENCY_UID} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = {PRODUCT_NAME};
\t\t\tpackageProductDependencies = (
\t\t\t\t{PKG_PRODUCT_UID} /* Supabase */,
\t\t\t\t{FIREBASE_PRODUCT_UID} /* FirebaseAnalytics */,
\t\t\t);
\t\t\tproductName = {PRODUCT_NAME};
\t\t\tproductReference = {APP_PRODUCT_REF} /* {PRODUCT_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{WIDGET_TARGET_UID} /* {WIDGET_PRODUCT_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {WIDGET_CONFIGLIST_TARGET} /* Build configuration list for PBXNativeTarget "{WIDGET_PRODUCT_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{WIDGET_SOURCES_PHASE} /* Sources */,
\t\t\t\t{WIDGET_FRAMEWORKS_PHASE} /* Frameworks */,
\t\t\t\t{WIDGET_RESOURCES_PHASE} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {WIDGET_PRODUCT_NAME};
\t\t\tproductName = {WIDGET_PRODUCT_NAME};
\t\t\tproductReference = {WIDGET_PRODUCT_REF} /* {WIDGET_PRODUCT_NAME}.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PROJECT_UID} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET_UID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tSystemCapabilities = {{
\t\t\t\t\t\t\t"com.apple.ApplicationGroups.iOS" = {{
\t\t\t\t\t\t\t\tenabled = 1;
\t\t\t\t\t\t\t}};
\t\t\t\t\t\t}};
\t\t\t\t\t}};
\t\t\t\t\t{WIDGET_TARGET_UID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tSystemCapabilities = {{
\t\t\t\t\t\t\t"com.apple.ApplicationGroups.iOS" = {{
\t\t\t\t\t\t\t\tenabled = 1;
\t\t\t\t\t\t\t}};
\t\t\t\t\t\t}};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {CONFIGLIST_PROJECT} /* Build configuration list for PBXProject "{PRODUCT_NAME}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tes,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {ROOT_GROUP};
\t\t\tpackageReferences = (
\t\t\t\t{PKG_REF_UID} /* XCRemoteSwiftPackageReference "supabase-swift" */,
\t\t\t\t{FIREBASE_PKG_REF_UID} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */,
\t\t\t);
\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET_UID} /* {PRODUCT_NAME} */,
\t\t\t\t{WIDGET_TARGET_UID} /* {WIDGET_PRODUCT_NAME} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCES_PHASE} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{emit_resources_phase("app")}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{WIDGET_RESOURCES_PHASE} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{emit_resources_phase("widget")}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SOURCES_PHASE} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{emit_sources_phase("app")}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{WIDGET_SOURCES_PHASE} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{emit_sources_phase("widget")}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{TARGET_DEPENDENCY_UID} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {WIDGET_TARGET_UID} /* {WIDGET_PRODUCT_NAME} */;
\t\t\ttargetProxy = {CONTAINER_PROXY_UID} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t{DEBUG_PROJECT_CFG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{RELEASE_PROJECT_CFG} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{DEBUG_TARGET_CFG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tAPP_GROUP_ID = "{APP_GROUP_ID_DEV}";
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Aliaro/Aliaro.entitlements;
\t\t\t\tINFOPLIST_FILE = Aliaro/Info.plist;
\t\t\t\tOTHER_LDFLAGS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"-ObjC",
\t\t\t\t);
\t\t\t\tCODE_SIGN_STYLE = Automatic;
{DEVELOPMENT_TEAM_LINE}\t\t\t\tCURRENT_PROJECT_VERSION = {CURRENT_PROJECT_VERSION};
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Aliaro Dev";
\t\t\t\tINFOPLIST_KEY_CFBundleURLTypes = (
\t\t\t\t\t{{
\t\t\t\t\t\tCFBundleTypeRole = Editor;
\t\t\t\t\t\tCFBundleURLSchemes = (
\t\t\t\t\t\t\taliaro,
\t\t\t\t\t\t);
\t\t\t\t\t}},
\t\t\t\t);
\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "Aliaro necesita la cámara para escanear el código QR de invitación al grupo familiar.";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleDefault;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = {MARKETING_VERSION};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID_DEV};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{RELEASE_TARGET_CFG} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tAPP_GROUP_ID = "{APP_GROUP_ID}";
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Aliaro/Aliaro.entitlements;
\t\t\t\tINFOPLIST_FILE = Aliaro/Info.plist;
\t\t\t\tOTHER_LDFLAGS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"-ObjC",
\t\t\t\t);
\t\t\t\tCODE_SIGN_STYLE = Automatic;
{DEVELOPMENT_TEAM_LINE}\t\t\t\tCURRENT_PROJECT_VERSION = {CURRENT_PROJECT_VERSION};
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Aliaro";
\t\t\t\tINFOPLIST_KEY_CFBundleURLTypes = (
\t\t\t\t\t{{
\t\t\t\t\t\tCFBundleTypeRole = Editor;
\t\t\t\t\t\tCFBundleURLSchemes = (
\t\t\t\t\t\t\taliaro,
\t\t\t\t\t\t);
\t\t\t\t\t}},
\t\t\t\t);
\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "Aliaro necesita la cámara para escanear el código QR de invitación al grupo familiar.";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleDefault;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = {MARKETING_VERSION};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{WIDGET_DEBUG_TARGET_CFG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tAPP_GROUP_ID = "{APP_GROUP_ID_DEV}";
\t\t\t\tCODE_SIGN_ENTITLEMENTS = AliaroWidgets/AliaroWidgetsExtension.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
{DEVELOPMENT_TEAM_LINE}\t\t\t\tCURRENT_PROJECT_VERSION = {CURRENT_PROJECT_VERSION};
\t\t\t\tINFOPLIST_FILE = AliaroWidgets/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = {MARKETING_VERSION};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {WIDGET_BUNDLE_ID_DEV};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{WIDGET_RELEASE_TARGET_CFG} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tAPP_GROUP_ID = "{APP_GROUP_ID}";
\t\t\t\tCODE_SIGN_ENTITLEMENTS = AliaroWidgets/AliaroWidgetsExtension.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
{DEVELOPMENT_TEAM_LINE}\t\t\t\tCURRENT_PROJECT_VERSION = {CURRENT_PROJECT_VERSION};
\t\t\t\tINFOPLIST_FILE = AliaroWidgets/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = {MARKETING_VERSION};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {WIDGET_BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{CONFIGLIST_PROJECT} /* Build configuration list for PBXProject "{PRODUCT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG_PROJECT_CFG} /* Debug */,
\t\t\t\t{RELEASE_PROJECT_CFG} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{CONFIGLIST_TARGET} /* Build configuration list for PBXNativeTarget "{PRODUCT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG_TARGET_CFG} /* Debug */,
\t\t\t\t{RELEASE_TARGET_CFG} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{WIDGET_CONFIGLIST_TARGET} /* Build configuration list for PBXNativeTarget "{WIDGET_PRODUCT_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{WIDGET_DEBUG_TARGET_CFG} /* Debug */,
\t\t\t\t{WIDGET_RELEASE_TARGET_CFG} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
\t\t{PKG_REF_UID} /* XCRemoteSwiftPackageReference "supabase-swift" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/supabase/supabase-swift";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 2.55.1;
\t\t\t}};
\t\t}};
\t\t{FIREBASE_PKG_REF_UID} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/firebase/firebase-ios-sdk";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 12.0.0;
\t\t\t}};
\t\t}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{PKG_PRODUCT_UID} /* Supabase */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {PKG_REF_UID} /* XCRemoteSwiftPackageReference "supabase-swift" */;
\t\t\tproductName = Supabase;
\t\t}};
\t\t{FIREBASE_PRODUCT_UID} /* FirebaseAnalytics */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {FIREBASE_PKG_REF_UID} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
\t\t\tproductName = FirebaseAnalytics;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {PROJECT_UID} /* Project object */;
}}
"""

os.makedirs(PROJ_DIR, exist_ok=True)
with open(os.path.join(PROJ_DIR, "project.pbxproj"), "w") as f:
    f.write(pbxproj)

# Persist uid map so re-runs are stable (same file -> same uid) across regenerations
with open(os.path.join(ROOT, ".pbx_uid_cache.json"), "w") as f:
    json.dump(_ids, f)

print(
    f"Generated project.pbxproj — app: {len(build_files['app'])} swift file(s), "
    f"{len(resource_build_files['app'])} resource(s); widget: {len(build_files['widget'])} swift file(s)."
)
