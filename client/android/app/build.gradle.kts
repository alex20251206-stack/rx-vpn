/*
 * Copyright (c) 2012-2016 Arne Schwabe
 * Distributed under the GNU GPL v2 with additional terms. For full terms see the file doc/LICENSE.txt
 */

plugins {
    alias(libs.plugins.android.application)
    id("checkstyle")
}

var swigcmd: String? = null
// Workaround for macOS(arm64) and macOS(intel) since it otherwise does not find swig and
// I cannot get the Exec task to respect the PATH environment :(
if (file("/opt/homebrew/bin/swig").exists())
    swigcmd = "/opt/homebrew/bin/swig"
else if (file("/usr/local/bin/swig").exists())
    swigcmd = "/usr/local/bin/swig"

// Same source as scripts/git-hooks/pre-commit (repo root VERSION).
fun readRxVpnSemverFromVersionFile(): Pair<String, Int> {
    val f = rootProject.projectDir.resolve("../../VERSION")
    val raw = if (f.exists()) f.readText().trim() else "0.0.0"
    val parts = raw.split(".").map { it.toIntOrNull() ?: 0 }
    val major = parts.getOrElse(0) { 0 }.coerceIn(0, 99)
    val minor = parts.getOrElse(1) { 0 }.coerceIn(0, 999)
    val patch = parts.getOrElse(2) { 0 }.coerceIn(0, 999)
    val versionName = "$major.$minor.$patch"
    val versionCode = major * 1_000_000 + minor * 1_000 + patch
    return versionName to versionCode
}

val (rxVpnVersionName, rxVpnVersionCode) = readRxVpnSemverFromVersionFile()

android {
    buildFeatures {
        aidl = true
        buildConfig = true
    }
    // Match applicationId so IDE/adb use the same package; Java/Kotlin code stays under de.blinkt.openvpn.*
    namespace = "com.ruoxue.vpn"
    compileSdk = 36
    //compileSdkPreview = "UpsideDownCake"

    // Also update runcoverity.sh
    ndkVersion = "29.0.14206865"

    defaultConfig {
        applicationId = "com.ruoxue.vpn"
        minSdk = 21
        targetSdk = 36
        //targetSdkPreview = "UpsideDownCake"
        versionCode = rxVpnVersionCode
        versionName = rxVpnVersionName
        externalNativeBuild {
            cmake {
                if (swigcmd != null) {
                    arguments("-DSWIG_EXECUTABLE=$swigcmd")
                }
            }
        }
    }


    //testOptions.unitTests.isIncludeAndroidResources = true

    externalNativeBuild {
        cmake {
            path = File("${projectDir}/src/main/cpp/CMakeLists.txt")
        }
    }

    sourceSets {
        getByName("main") {
            assets.srcDirs("src/main/assets", "build/ovpnassets")

        }

        create("ui") {
        }

        getByName("debug") {
        }

        getByName("release") {
        }
    }

    signingConfigs {
        create("release") {
            // ~/.gradle/gradle.properties
            val keystoreFile: String? by project
            storeFile = keystoreFile?.let { file(it) }
            val keystorePassword: String? by project
            storePassword = keystorePassword
            val keystoreAliasPassword: String? by project
            keyPassword = keystoreAliasPassword
            val keystoreAlias: String? by project
            keyAlias = keystoreAlias
            enableV1Signing = true
            enableV2Signing = true
        }

        create("releaseOvpn2") {
            // ~/.gradle/gradle.properties
            val keystoreO2File: String? by project
            storeFile = keystoreO2File?.let { file(it) }
            val keystoreO2Password: String? by project
            storePassword = keystoreO2Password
            val keystoreO2AliasPassword: String? by project
            keyPassword = keystoreO2AliasPassword
            val keystoreO2Alias: String? by project
            keyAlias = keystoreO2Alias
            enableV1Signing = true
            enableV2Signing = true
        }

    }

    lint {
        enable += setOf("BackButton", "EasterEgg", "StopShip", "IconExpectedSize", "GradleDynamicVersion", "NewerVersionAvailable")
        checkOnly += setOf("ImpliedQuantity", "MissingQuantity")
        disable += setOf("MissingTranslation", "UnsafeNativeCodeLocation")
    }


    flavorDimensions += listOf("implementation", "ovpnimpl")

    productFlavors {
        create("ui") {
            dimension = "implementation"
        }

        create("ovpn23")
        {
            dimension = "ovpnimpl"
            buildConfigField("boolean", "openvpn3", "true")
            // CMake must not infer ovpn3 from CMAKE_LIBRARY_OUTPUT_DIRECTORY (AGP uses cxx/<hash>/ paths).
            externalNativeBuild {
                cmake {
                    arguments("-DRX_ENABLE_OVPN3_NATIVE=1")
                }
            }
        }

        create("ovpn2")
        {
            dimension = "ovpnimpl"
            buildConfigField("boolean", "openvpn3", "false")
            externalNativeBuild {
                cmake {
                    arguments("-DRX_ENABLE_OVPN3_NATIVE=0")
                }
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (project.hasProperty("icsopenvpnDebugSign")) {
                logger.warn("property icsopenvpnDebugSign set, using debug signing for release")
                signingConfig = android.signingConfigs.getByName("debug")
            } else {
                productFlavors["ovpn23"].signingConfig = signingConfigs.getByName("release")
                productFlavors["ovpn2"].signingConfig = signingConfigs.getByName("releaseOvpn2")
            }
        }
    }

    compileOptions {
        targetCompatibility = JavaVersion.VERSION_17
        sourceCompatibility = JavaVersion.VERSION_17
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("x86", "x86_64", "armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    bundle {
        codeTransparency {
            signing {
                val keystoreTPFile: String? by project
                storeFile = keystoreTPFile?.let { file(it) }
                val keystoreTPPassword: String? by project
                storePassword = keystoreTPPassword
                val keystoreTPAliasPassword: String? by project
                keyPassword = keystoreTPAliasPassword
                val keystoreTPAlias: String? by project
                keyAlias = keystoreTPAlias

                if (keystoreTPFile?.isEmpty() ?: true)
                    println("keystoreTPFile not set, disabling transparency signing")
                if (keystoreTPPassword?.isEmpty() ?: true)
                    println("keystoreTPPassword not set, disabling transparency signing")
                if (keystoreTPAliasPassword?.isEmpty() ?: true)
                    println("keystoreTPAliasPassword not set, disabling transparency signing")
                if (keystoreTPAlias?.isEmpty() ?: true)
                    println("keyAlias not set, disabling transparency signing")

            }
        }
    }
}

androidComponents {
    // OVPN3 Java bindings are generated by SWIG. If SWIG is unavailable on the
    // local machine, disable ovpn23 variants to keep builds working on ovpn2.
    beforeVariants(selector().withFlavor("ovpnimpl" to "ovpn23")) { variantBuilder ->
        variantBuilder.enable = false
    }
}

// NOTE:
// The legacy `applicationVariants` API is removed in AGP 9+.
// OVPN3 SWIG source generation should be migrated to androidComponents API.
// Keeping build script compatible first to unblock sync/build.


dependencies {
    // https://maven.google.com/web/index.html
    implementation(libs.androidx.annotation)
    implementation(libs.androidx.core.ktx)

    uiImplementation(libs.android.view.material)
    uiImplementation(libs.androidx.activity)
    uiImplementation(libs.androidx.activity.ktx)
    uiImplementation(libs.androidx.appcompat)
    uiImplementation(libs.androidx.cardview)
    uiImplementation(libs.androidx.viewpager2)
    uiImplementation(libs.androidx.constraintlayout)
    uiImplementation(libs.androidx.core.ktx)
    uiImplementation(libs.androidx.fragment.ktx)
    uiImplementation(libs.androidx.lifecycle.runtime.ktx)
    uiImplementation(libs.androidx.lifecycle.viewmodel.ktx)
    uiImplementation(libs.androidx.preference.ktx)
    uiImplementation(libs.androidx.recyclerview)
    uiImplementation(libs.androidx.security.crypto)
    uiImplementation(libs.androidx.webkit)
    uiImplementation(libs.kotlin)
    uiImplementation(libs.mpandroidchart)
    uiImplementation(libs.square.okhttp)

    testImplementation(libs.androidx.test.core)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin)
    testImplementation(libs.mockito.core)
    testImplementation(libs.robolectric)
}

fun DependencyHandler.uiImplementation(dependencyNotation: Any): Dependency? =
    add("uiImplementation", dependencyNotation)
