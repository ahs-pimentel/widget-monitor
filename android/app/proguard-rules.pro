# Modelos do contrato JSON (kotlinx.serialization).
-keepclassmembers class me.o2d.odoismonitor.data.** { *; }
-dontwarn okhttp3.internal.platform.**

# ML Kit (leitor de QR do Play Services) cria os registradores por reflexão:
# sem estas regras o R8 remove os construtores e o leitor falha ao abrir
# (NoSuchMethodException: CommonComponentRegistrar.<init>).
-keep class * implements com.google.firebase.components.ComponentRegistrar { public <init>(); }
-keep class com.google.mlkit.common.internal.** { *; }
-keep class com.google.mlkit.vision.common.internal.** { *; }
-keep class com.google.mlkit.vision.codescanner.** { *; }
