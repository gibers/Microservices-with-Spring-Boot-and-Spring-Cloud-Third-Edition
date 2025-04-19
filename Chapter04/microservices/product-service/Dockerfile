FROM eclipse-temurin:21-jre-jammy as builder
WORKDIR extracted
ADD ./build/libs/*.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination productService

FROM eclipse-temurin:21-jre-jammy
WORKDIR application
COPY --from=builder extracted/productService/dependencies/ ./
COPY --from=builder extracted/productService/spring-boot-loader/ ./
COPY --from=builder extracted/productService/snapshot-dependencies/ ./
COPY --from=builder extracted/productService/application/ ./

EXPOSE 8080

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]