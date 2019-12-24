FROM gradle:jdk11 as BUILD

COPY --chown=gradle:gradle . /project
RUN gradle -i -s -b /project/build.gradle clean test build && \
    rm -rf /project/build/install/*/bin/*.bat

FROM openjdk:11-jre-slim
ENV PORT 8080
EXPOSE 8080
RUN mkdir -p /opt/bin
COPY --from=BUILD /project/build/libs/* /opt/bin
WORKDIR /opt/bin
CMD ["/bin/bash", "-c", "find -type f -name '*.jar' | xargs java -jar"]
