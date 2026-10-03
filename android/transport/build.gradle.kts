plugins {
    `java-library`
}

dependencies {
    implementation(project(":protocol"))
    implementation("io.netty:netty-codec-http:4.2.18.Final")
    implementation("io.netty:netty-handler:4.2.18.Final")
    testImplementation("junit:junit:4.13.2")
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

sourceSets.test {
    resources.srcDir(rootProject.layout.projectDirectory.dir("../shared/ProtocolFixtures"))
}

tasks.test {
    useJUnit()
    maxParallelForks = 1
}
