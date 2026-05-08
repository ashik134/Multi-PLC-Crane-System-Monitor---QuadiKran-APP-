allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force all plugin subprojects to use Java 17 and Kotlin JVM target 17 so
// that javac/kotlinc targets stay consistent and the obsolete-options
// warnings disappear.
subprojects {
    afterEvaluate {
        // Android library plugins (e.g. flutter_foreground_task)
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        // Align Kotlin JVM target to 17 for every Kotlin compile task in
        // every subproject (covers both KotlinCompile and KotlinJvmCompile).
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
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
