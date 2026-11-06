import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.isFile) {
        localPropertiesFile.inputStream().use(::load)
    }
}

fun signingProperty(propertyName: String, environmentName: String): String? =
    localProperties.getProperty(propertyName)
        ?: providers.environmentVariable(environmentName).orNull
            ?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingProperty(
    "typecarrier.android.release.storeFile",
    "TYPECARRIER_ANDROID_RELEASE_STORE_FILE",
)
val releaseStorePassword = signingProperty(
    "typecarrier.android.release.storePassword",
    "TYPECARRIER_ANDROID_RELEASE_STORE_PASSWORD",
)
val releaseKeyAlias = signingProperty(
    "typecarrier.android.release.keyAlias",
    "TYPECARRIER_ANDROID_RELEASE_KEY_ALIAS",
)
val releaseKeyPassword = signingProperty(
    "typecarrier.android.release.keyPassword",
    "TYPECARRIER_ANDROID_RELEASE_KEY_PASSWORD",
)
val hasReleaseSigningConfig = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "org.typecarrier.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "org.typecarrier.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 5
        versionName = "0.1.5"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // The ABIs script/build_carrier_core_android.sh builds the Rust core for.
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.05.01"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.navigation:navigation-compose:2.9.8")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    // The Rust protocol core's Kotlin bindings call into libcarrier_core.so through JNA.
    implementation("net.java.dev.jna:jna:5.17.0@aar")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    testImplementation("net.java.dev.jna:jna:5.17.0")
}

// The Rust protocol core (Core/carrier-core): build it for every ABI before compiling, and point
// JVM unit tests at the host build so they run the same code as the device.
val carrierCoreDir = rootDir.resolve("../../Core/carrier-core")
val buildCarrierCore by tasks.registering(Exec::class) {
    description = "Builds the Rust protocol core for Android and regenerates its Kotlin bindings."
    inputs.dir(carrierCoreDir.resolve("src"))
    inputs.file(carrierCoreDir.resolve("Cargo.toml"))
    inputs.file(carrierCoreDir.resolve("Cargo.lock"))
    outputs.dir(layout.projectDirectory.dir("src/main/jniLibs"))
    outputs.file(carrierCoreDir.resolve("target/release/libcarrier_core.dylib"))
    commandLine(rootDir.resolve("../../script/build_carrier_core_android.sh").absolutePath)
}
tasks.named("preBuild") { dependsOn(buildCarrierCore) }
tasks.withType<Test>().configureEach {
    dependsOn(buildCarrierCore)
    systemProperty("jna.library.path", carrierCoreDir.resolve("target/release").absolutePath)
}
