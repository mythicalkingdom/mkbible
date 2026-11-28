import java.net.URL
import java.util.Properties
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.mythicalkingdom.mkbible"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.mythicalkingdom.mkbible"
        minSdk = 24
        targetSdk = 35
        versionCode = 4
        versionName = "0.1.3"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }
    // Release signing: the key lives outside the repository.  The properties file (storeFile, storePassword, keyAlias,
    // keyPassword) is read from $MKBIBLE_KEYSTORE_PROPERTIES, else ~/.config/mkbible/keystore.properties.  Without it
    // the release build is signed with the debug key (fine for trying it out, not for publishing).
    val keyProps = Properties().apply {
        val f = File(System.getenv("MKBIBLE_KEYSTORE_PROPERTIES") ?: (System.getProperty("user.home") + "/.config/mkbible/keystore.properties"))
        if (f.exists()) f.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) create("release") {
            storeFile = File(keyProps.getProperty("storeFile"))
            storePassword = keyProps.getProperty("storePassword")
            keyAlias = keyProps.getProperty("keyAlias")
            keyPassword = keyProps.getProperty("keyPassword")
        }
    }
    // Release build: R8 shrinks the code (Compose brings a lot), resources are shrunk, and one APK per CPU is made
    // (plus a universal one for emulators).
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "x86_64")
            isUniversalApk = true
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}
dependencies {
    val bom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(bom)
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.ui:ui")
}

// The standard modules bundled for the first run: the World English Bible Updated (eBible.org), the ASV and the KJV
// with Strong's numbers, and the Strong's Greek and Hebrew dictionaries (CrossWire).  All are public domain texts; the
// CrossWire KJV module itself is distributed under the GPL.  They are not kept in git: this task
// downloads whatever is missing into src/main/assets/sword.
val ebible = "https://ebible.org/sword/packages"
val crosswire = "https://www.crosswire.org/ftpmirror/pub/sword/raw/packages"
val bundledModules = listOf("engwebu2025eb" to ebible, "ASV" to crosswire, "KJV" to crosswire, "StrongsGreek" to crosswire, "StrongsHebrew" to crosswire)
val fetchBundledModules by tasks.registering {
    val dest = layout.projectDirectory.dir("src/main/assets/sword").asFile
    val cache = layout.buildDirectory.dir("bundled").get().asFile
    outputs.dir(dest)
    onlyIf { bundledModules.any { (id, _) -> !File(dest, "mods.d/${id.lowercase()}.conf").exists() } }
    doLast {
        cache.mkdirs()
        for ((id, base) in bundledModules) {
            if (File(dest, "mods.d/${id.lowercase()}.conf").exists()) continue
            val zip = File(cache, "$id.zip")
            URL("$base/$id.zip").openStream().use { i -> zip.outputStream().use { o -> i.copyTo(o) } }
            ZipInputStream(zip.inputStream()).use { z ->
                while (true) {
                    val e = z.nextEntry ?: break
                    if (e.isDirectory) continue
                    val f = File(dest, e.name)
                    f.parentFile.mkdirs()
                    f.outputStream().use { o -> z.copyTo(o) }
                }
            }
        }
    }
}

// The Pascal core is cross-compiled outside Gradle (native/build.sh); stop early with a clear message if that was skipped.
val checkNativeLibs by tasks.registering {
    val dir = layout.projectDirectory.dir("src/main/jniLibs").asFile
    doLast {
        val missing = listOf("arm64-v8a", "x86_64").filter { !File(dir, "$it/libmkbibjni.so").exists() }
        if (missing.isNotEmpty())
            throw GradleException("libmkbibjni.so is missing for ${missing.joinToString()}: run native/build.sh a64 and native/build.sh x64 first (see android/README.md)")
    }
}
tasks.named("preBuild") { dependsOn(fetchBundledModules, checkNativeLibs) }
