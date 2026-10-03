plugins {
    `java-library`
}

dependencies {
    implementation("org.bouncycastle:bcprov-jdk15to18:1.86")
    // Streaming JSON only; schemas impose explicit duplicate, depth and resource limits.
    implementation("com.google.code.gson:gson:2.11.0")
}

val pairingFixtures = rootProject.layout.projectDirectory.dir("../shared/ProtocolFixtures")
sourceSets.test {
    resources.srcDir(pairingFixtures)
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(11)
    options.encoding = "UTF-8"
    options.compilerArgs.addAll(listOf("-Xlint:all", "-Werror", "-proc:none"))
}

tasks.test {
    // Protocol suites are mandatory JavaExec mains below, not framework-discovered tests.
    failOnNoDiscoveredTests.set(false)
}

val invitationInteropTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.PairingInvitationTest")
    args(pairingFixtures.file("pairing-invitations-v1.tsv").asFile.absolutePath)
}

val pairingCanonicalCodecTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.PairingCanonicalCodecTest")
}

val pairingPayloadDecoderTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.PairingPayloadDecoderTest")
    args(pairingFixtures.file("public-swift-engine-v1.tsv").asFile.absolutePath)
}

val pairingUnicodeParityTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.PairingUnicodeParityTest")
    args(pairingFixtures.file("public-foundation-unicode-name-v1.tsv").asFile.absolutePath)
}

val pairingCryptoInteropTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.BouncyCastlePairingCryptoTest")
    args(pairingFixtures.file("public-swift-engine-v1.tsv").asFile.absolutePath)
}

val viewerPairingAuthenticatorTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.ViewerPairingAuthenticatorTest")
    args(pairingFixtures.file("public-swift-engine-v1.tsv").asFile.absolutePath)
}

val viewerPairRecordTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.ViewerPairRecordTest")
    args(pairingFixtures.file("public-swift-engine-v1.tsv").asFile.absolutePath)
}

val viewerBootstrapReducerTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.ViewerBootstrapReducerTest")
    args(pairingFixtures.file("public-swift-engine-v1.tsv").asFile.absolutePath)
}

val viewerReconnectAuthenticatorTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.ViewerReconnectAuthenticatorTest")
    args(pairingFixtures.file("public-swift-engine-v1.tsv").asFile.absolutePath,
        pairingFixtures.file("public-swift-saved-pair-reconnect-v1.tsv").asFile.absolutePath)
}

tasks.check {
    dependsOn(invitationInteropTest, pairingCanonicalCodecTest, pairingPayloadDecoderTest, pairingUnicodeParityTest, pairingCryptoInteropTest, viewerPairingAuthenticatorTest, viewerPairRecordTest, viewerBootstrapReducerTest, viewerReconnectAuthenticatorTest)
}
