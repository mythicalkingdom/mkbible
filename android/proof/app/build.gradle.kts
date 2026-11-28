import java.net.URL
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "org.mkbible.proof"
    compileSdk = 35
    defaultConfig {
        applicationId = "org.mkbible.proof"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.0.1"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
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

// The module bundled for the first run is public domain (World English Bible, from eBible.org's Sword repository).
// It is not kept in git: this task downloads it into src/main/assets/sword when it is missing.
val bundledModule = "engwebu2025eb"
val fetchBundledModule by tasks.registering {
    val dest = layout.projectDirectory.dir("src/main/assets/sword").asFile
    val zip = layout.buildDirectory.file("bundled/$bundledModule.zip").get().asFile
    outputs.dir(dest)
    onlyIf { !File(dest, "mods.d/$bundledModule.conf").exists() }
    doLast {
        zip.parentFile.mkdirs()
        URL("https://ebible.org/sword/packages/$bundledModule.zip").openStream().use { i ->
            zip.outputStream().use { o -> i.copyTo(o) }
        }
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

// The Pascal core is cross-compiled outside Gradle (native/build.sh); stop early with a clear message if that was skipped.
val checkNativeLibs by tasks.registering {
    val dir = layout.projectDirectory.dir("src/main/jniLibs").asFile
    doLast {
        val missing = listOf("arm64-v8a", "x86_64").filter { !File(dir, "$it/libmkbibjni.so").exists() }
        if (missing.isNotEmpty())
            throw GradleException("libmkbibjni.so is missing for ${missing.joinToString()}: run native/build.sh a64 and native/build.sh x64 first (see android/README.md)")
    }
}
tasks.named("preBuild") { dependsOn(fetchBundledModule, checkNativeLibs) }
