allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val sourceRoot = project.projectDir.toPath().toAbsolutePath().root
    val outputRoot = newBuildDir.asFile.toPath().toAbsolutePath().root
    if (sourceRoot != outputRoot) {
        // AGP's GenerateTestConfig uses paths relative to each plugin's source.
        // Windows cannot make those paths relative across C: and E: volumes.
        // Keep external plugin output on its source volume, outside Pub sources
        // when LOCALAPPDATA is available there. App output stays in build/app.
        val projectKey = rootProject.projectDir.absolutePath.hashCode().toUInt().toString(16)
        val localCache = System.getenv("LOCALAPPDATA")?.let {
            file("$it/SignVoice/gradle-build/$projectKey/${project.name}")
        }
        val pluginOutput = if (localCache?.toPath()?.toAbsolutePath()?.root == sourceRoot) {
            localCache
        } else {
            project.projectDir.resolve("build")
        }
        project.layout.buildDirectory.fileValue(pluginOutput)
    } else {
        project.layout.buildDirectory.value(newBuildDir.dir(project.name))
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
