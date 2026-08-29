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
    // jni / jni_flutter 的源码来自 Windows 用户缓存（通常在 C 盘）。
    // 将其 CMake 产物强制写入 F 盘会触发 AGP 9 的跨盘 Path.relativize
    // 异常（"other has different root"），因此让这两个原生模块留在源码盘。
    if (project.name == "jni" || project.name == "jni_flutter") {
        project.layout.buildDirectory.value(project.layout.projectDirectory.dir("build"))
    } else {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
