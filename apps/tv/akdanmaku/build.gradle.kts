plugins {
    alias(gradleLibs.plugins.android.library)
    alias(gradleLibs.plugins.kotlin.android)
}

val natives by configurations.creating
val copyAndroidNatives by tasks.registering {
    val outputDirectory = layout.buildDirectory.dir("generated/jniLibs")
    inputs.files(natives)
    outputs.dir(outputDirectory)
    doLast {
        for (nativeJar in natives.files) {
            val abi = nativeJar.name.substringAfter("natives-").removeSuffix(".jar")
            copy {
                from(zipTree(nativeJar)) { include("*.so") }
                into(outputDirectory.get().dir(abi))
            }
        }
    }
}

android {
    namespace = "com.kuaishou.akdanmaku"
    compileSdk = AppConfiguration.compileSdk
    defaultConfig { minSdk = AppConfiguration.minSdk }
    buildFeatures { buildConfig = true }
    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("generated/jniLibs"))
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
kotlin { jvmToolchain(17) }
tasks.named("preBuild") { dependsOn(copyAndroidNatives) }

dependencies {
    implementation("com.badlogicgames.gdx:gdx:1.12.0")
    implementation("com.badlogicgames.gdx:gdx-backend-android:1.12.0")
    implementation("com.badlogicgames.ashley:ashley:1.7.4")
    implementation(androidx.core.ktx)
    for (abi in listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")) {
        natives("com.badlogicgames.gdx:gdx-platform:1.12.0:natives-$abi")
    }
}
