import java.io.File as LocalFile
import java.security.MessageDigest as LocalMessageDigest
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.OutputDirectory
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

abstract class PrepareWebRtcNotices : Sync() {
    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty
}

// The unchanged upstream SDK classes require javac 21; emitted app classes stay
// Java 17. Keep AGP's Android platform APIs, not a desktop --release replacement.
check(JavaVersion.current() == JavaVersion.VERSION_21) {
    "The receiver preview requires a local JDK 21 build JVM (JAVA_HOME)."
}

val derivedWebrtcSHA256 = "e98a90d72fa186d9feb92ea3cde3a6dda06e68361c061bce9f72bf854c92bf6d"
val derivedWebrtcPath = providers.gradleProperty("belugaDerivedWebrtcAar").orNull
    ?: error("Supply -PbelugaDerivedWebrtcAar=/absolute/canonical/libwebrtc-derived.aar")
fun checkedDerivedWebrtcAar(): LocalFile {
    val artifact = LocalFile(derivedWebrtcPath)
    check(artifact.isAbsolute && artifact.canonicalPath == derivedWebrtcPath && artifact.isFile) {
        "belugaDerivedWebrtcAar must name an existing canonical absolute regular file"
    }
    check(artifact.length() in 1..(64L * 1024 * 1024)) { "Unexpected derived WebRTC AAR size" }
    val digest = LocalMessageDigest.getInstance("SHA-256")
    artifact.inputStream().buffered().use { input ->
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    check(actual == derivedWebrtcSHA256) { "Derived WebRTC AAR does not match the reviewed digest" }
    return artifact
}
val derivedWebrtcAar = checkedDerivedWebrtcAar()
val verifyDerivedWebrtcAar = tasks.register("verifyDerivedWebrtcAar") {
    // No output/cached-success marker: recheck the external input on every build.
    doLast { checkedDerivedWebrtcAar() }
}
val webRtcAdapterDirectory = rootProject.layout.projectDirectory.dir("webrtc-adapter")

android {
    namespace = "com.elamin.beluga.preview"
    compileSdk = 36
    buildToolsVersion = "36.0.0"

    defaultConfig {
        applicationId = "com.elamin.beluga.android.preview"
        // The durable secure-store contract and packaged networking require API 27+.
        minSdk = 27
        targetSdk = 36
        versionCode = 3
        versionName = "0.1.2-receiver-preview"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
    // Preserve the exact reviewed native payloads; no strip/relink/header edits.
    packaging.jniLibs.keepDebugSymbols.add("**/libjingle_peerconnection_so.so")
    packaging.resources {
        // JAR class-loader indexes and Java module descriptors are not Android resources.
        // Preserve all runtime classes and ship license text separately under assets.
        excludes.add("META-INF/INDEX.LIST")
        excludes.add("META-INF/versions/11/module-info.class")
        // Each Netty module contributes distinct version keys; retain every module.
        merges.add("META-INF/io.netty.versions.properties")
    }
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    testOptions {
        unitTests.isReturnDefaultValues = false
    }
    sourceSets.getByName("main").java.directories.add(webRtcAdapterDirectory.dir("receiver").asFile.path)
    sourceSets.getByName("test").resources.directories.add(
        rootProject.layout.projectDirectory.dir("../shared/ProtocolFixtures").asFile.path
    )
}

androidComponents.onVariants { variant ->
    val prepareWebRtcNotices = tasks.register<PrepareWebRtcNotices>(
        "prepare${variant.name.replaceFirstChar { it.uppercase() }}WebRtcNotices"
    ) {
        from(webRtcAdapterDirectory) {
            include("LICENSE.webrtc", "PATENTS.webrtc", "NOTICE.beluga")
            into("third-party/webrtc-sdk-150.7871.01")
        }
        outputDirectory.set(layout.buildDirectory.dir("generated/webrtc-notices/${variant.name}"))
        into(outputDirectory)
    }
    variant.sources.assets?.addGeneratedSourceDirectory(
        prepareWebRtcNotices, PrepareWebRtcNotices::outputDirectory
    )
}

tasks.named("preBuild") { dependsOn(verifyDerivedWebrtcAar) }

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    // PlaybackOutputObserver and patched WebRtcAudioTrack are already in this
    // single artifact. Never also compile webrtc-adapter/src or add the raw AAR.
    implementation(files(derivedWebrtcAar))
    implementation(project(":protocol"))
    implementation(project(":transport"))
    implementation(platform("androidx.compose:compose-bom:2025.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    testImplementation("junit:junit:4.13.2")
}
