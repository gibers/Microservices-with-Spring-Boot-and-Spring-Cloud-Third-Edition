FROM eclipse-temurin:17.0.5_8-jre-focal as builder
WORKDIR extracted
ADD ./build/libs/*.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination dest

FROM eclipse-temurin:17.0.5_8-jre-focal
WORKDIR application
COPY --from=builder extracted/dest/dependencies/ ./
COPY --from=builder extracted/dest/spring-boot-loader/ ./
COPY --from=builder extracted/dest/snapshot-dependencies/ ./
COPY --from=builder extracted/dest/application/ ./

EXPOSE 8080

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]