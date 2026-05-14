package com.kepler.atlas;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * ATLAS — Relay node. Runs TCP server (7002) and HTTP REST server (8080)
 * in separate single-thread executors, sharing a ConcurrentHashMap of missions.
 */
public class AtlasMain {

    public static void main(String[] args) throws InterruptedException {
        log("ATLAS iniciando...");

        AgencyRegistry registry    = new AgencyRegistry();
        PriorityClassifier clf     = new PriorityClassifier();

        TcpServer  tcpServer  = new TcpServer(registry, clf);
        RestServer restServer = new RestServer(registry, clf);

        ExecutorService tcpExecutor  = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "atlas-tcp");
            t.setDaemon(false);
            return t;
        });
        ExecutorService httpExecutor = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "atlas-http");
            t.setDaemon(false);
            return t;
        });

        tcpExecutor.submit(tcpServer);
        httpExecutor.submit(restServer);

        log("TCP  escuchando en puerto 7002");
        log("HTTP escuchando en puerto 8080");

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            log("Apagando ATLAS...");
            tcpExecutor.shutdownNow();
            httpExecutor.shutdownNow();
        }));

        // Keep main thread alive
        tcpExecutor.awaitTermination(Long.MAX_VALUE, TimeUnit.DAYS);
    }

    public static void log(String msg) {
        System.out.printf("[ATLAS %s] %s%n",
            java.time.Instant.now().toString(), msg);
    }
}
