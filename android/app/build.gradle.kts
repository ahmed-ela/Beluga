import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.elamin.beluga.preview"
    compileSdk = 36
    buildToolsVersion = "36.0.0"

    defaultConfig {
        applicationId = "com.elamin.beluga.android.preview"
        // The durable secure-store contract and packaged networking require API 27+.
        minSdk = 27
        targetSdk = 36
        versionCode = 2
        versionName = "0.1.1-pairing-preview"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
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
    sourceSets.getByName("test").resources.directories.add(
        rootProject.layout.projectDirectory.dir("../shared/ProtocolFixtures").asFile.path
    )
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
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
