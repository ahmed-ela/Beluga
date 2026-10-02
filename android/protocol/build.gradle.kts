plugins {
    `java-library`
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
    options.compilerArgs.addAll(listOf("-Xlint:all", "-Werror"))
}

val invitationInteropTest by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.elamin.beluga.protocol.PairingInvitationTest")
    args(pairingFixtures.file("pairing-invitations-v1.tsv").asFile.absolutePath)
}

tasks.check {
    dependsOn(invitationInteropTest)
}
