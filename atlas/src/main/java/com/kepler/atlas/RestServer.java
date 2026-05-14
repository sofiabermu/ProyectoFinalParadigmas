package com.kepler.atlas;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;

/**
 * HTTP REST server on port 8080. Exposes:
 *   GET /api/history/{mission_id}  — proxies query to HERMES → Voyager chain
 *   GET /api/health                — liveness check
 */
public class RestServer implements Runnable {

    private static final int PORT = Integer.parseInt(
        System.getenv().getOrDefault("ATLAS_HTTP_PORT", "8080"));

    private final AgencyRegistry     registry;
    private final PriorityClassifier clf;
    private final ObjectMapper        mapper = new ObjectMapper();

    public RestServer(AgencyRegistry registry, PriorityClassifier clf) {
        this.registry = registry;
        this.clf      = clf;
    }

    @Override
    public void run() {
        try {
            HttpServer server = HttpServer.create(new InetSocketAddress(PORT), 50);
            server.createContext("/api/history", this::handleHistory);
            server.createContext("/api/health",  this::handleHealth);
            server.setExecutor(java.util.concurrent.Executors.newCachedThreadPool());
            server.start();
            AtlasMain.log("RestServer ready on :" + PORT);
        } catch (IOException e) {
            AtlasMain.log("RestServer error: " + e.getMessage());
        }
    }

    private void handleHealth(HttpExchange ex) throws IOException {
        if (!"GET".equals(ex.getRequestMethod())) { sendJson(ex, 405, "{\"error\":\"Method Not Allowed\"}"); return; }
        ObjectNode node = mapper.createObjectNode();
        node.put("status", "UP");
        node.put("active_missions", registry.getActiveMissionsCount());
        node.put("timestamp_utc", Instant.now().toString());
        sendJson(ex, 200, mapper.writeValueAsString(node));
    }

    private void handleHistory(HttpExchange ex) throws IOException {
        if (!"GET".equals(ex.getRequestMethod())) { sendJson(ex, 405, "{\"error\":\"Method Not Allowed\"}"); return; }

        // Extract mission_id from /api/history/{mission_id}
        String path      = ex.getRequestURI().getPath();
        String missionId = path.replaceFirst("^/api/history/?", "").trim();
        if (missionId.isEmpty()) {
            sendJson(ex, 400, "{\"error\":\"mission_id required\"}");
            return;
        }

        AtlasMain.log("GET /api/history/" + missionId + " — querying HERMES chain");

        // Build QUERY_HISTORY request for HERMES
        ObjectNode req = mapper.createObjectNode();
        req.put("type",       "QUERY_HISTORY");
        req.put("mission_id", missionId);
        req.put("limit",      20);

        String hermesHost = System.getenv().getOrDefault("HERMES_HOST", "localhost");
        int    hermesPort = Integer.parseInt(System.getenv().getOrDefault("HERMES_TCP_PORT", "7003"));

        String responseJson = queryHermesTcp(hermesHost, hermesPort, mapper.writeValueAsString(req));

        sendJson(ex, 200, responseJson);
    }

    private String queryHermesTcp(String host, int port, String jsonRequest) {
        int attempts = 0;
        while (attempts < 3) {
            try (java.net.Socket sock = new java.net.Socket(host, port);
                 PrintWriter out = new PrintWriter(new OutputStreamWriter(sock.getOutputStream(), StandardCharsets.UTF_8), true);
                 BufferedReader in  = new BufferedReader(new InputStreamReader(sock.getInputStream(), StandardCharsets.UTF_8))) {

                sock.setSoTimeout(10000);
                out.println(jsonRequest);
                String line = in.readLine();
                if (line != null) {
                    AtlasMain.log("HERMES history response received (" + line.length() + " chars)");
                    return line;
                }
            } catch (Exception e) {
                AtlasMain.log("HERMES query attempt " + (attempts + 1) + " failed: " + e.getMessage());
                attempts++;
                try { Thread.sleep((long) Math.pow(2, attempts) * 500); } catch (InterruptedException ie) { break; }
            }
        }
        return "{\"error\":\"HERMES unreachable after 3 retries\"}";
    }

    private void sendJson(HttpExchange ex, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().set("Content-Type", "application/json; charset=UTF-8");
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }
}
