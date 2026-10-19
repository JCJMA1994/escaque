# Se construye desde la carpeta que contiene tablero_engine/ y tablero_server/:
#   docker build -f tablero_server/Dockerfile .
FROM dart:3.13 AS build
WORKDIR /src
COPY tablero_engine/ tablero_engine/
COPY tablero_server/pubspec.yaml tablero_server/
WORKDIR /src/tablero_server
RUN dart pub get
COPY tablero_server/ .
RUN dart pub get --offline && dart test && dart compile exe bin/server.dart -o bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /etc/ssl/certs/ /etc/ssl/certs/
COPY --from=build /src/tablero_server/bin/server /app/server
EXPOSE 8080
CMD ["/app/server"]
