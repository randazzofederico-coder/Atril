allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory
    .dir("../../build")
    .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // 1. Configuración de directorios
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // 2. EL PARCHE (Movido aquí ARRIBA para que corra antes de la evaluación)
    afterEvaluate {
        // Buscamos la extensión de Android de forma segura
        val android = extensions.findByName("android")
        // Verificamos si es una extensión válida de Android (casteo seguro)
        if (android is com.android.build.gradle.BaseExtension) {
            // Si no tiene namespace, le ponemos el group (ej: com.example...)
            if (android.namespace == null) {
                android.namespace = group.toString()
            }
        }
    }
}

// 3. Dependencias de evaluación (ESTO SIEMPRE AL FINAL DE LOS SUBPROJECTS)
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}