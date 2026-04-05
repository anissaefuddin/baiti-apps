allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // Force all library subprojects to compile against the same SDK level
    // as the app so that attributes like android:attr/lStar (added in API 31)
    // are always resolved correctly (e.g. the `printing` package).
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {
            if (it.compileSdkVersion?.replace("android-", "")?.toIntOrNull() ?: 0 < 31) {
                it.compileSdkVersion(36)
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.3.15")
    }
}