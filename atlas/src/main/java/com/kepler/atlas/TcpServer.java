package com.kepler.atlas;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.*;
import java.net.ServerSocket;
import java.net.Socket;
import java.time.Instant;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * TCP server on port 7002. Receives newline-delimited JSON from HERMES,
 * enriches the payload, then POSTs to GROUND via HTTP.
 */
public class TcpServer implements Runnable {

    private static final int PORT        = Integer.parseInt(System.getenv().getOrDefault("ATLAS_TCP_PORT", "7002"));
    private static final int BACKLOG     = 50;

    private final AgencyRegistry     registry;
    private final PriorityClassifier clf;
    private final ObjectMapper        mapper = new ObjectMapper();
    private final ExecutorService     pool   = Executors.newCachedThreadPool();

    public TcpServer(AgencyRegistry registry, PriorityClassifier clf) {
        this.registry = registry;
        this.clf      = clf;
    }

    @Override
    public void run() {
        try (ServerSocket server = new ServerSocket(PORT, BACKLOG)) {
            AtlasMain.log("TcpServer ready on :" + PORT);
            while (!Thread.currentThread().isInterrupted()) {
                Socket client = server.accept();
                pool.submit(() -> handleClient(client));
            }
        } catch (IOException e) {
            AtlasMain.log("TcpServer error: " + e.getMessage());
        }
    }

    private void handleClient(Socket client) {
        String remote = client.getRemoteSocketAddress().toString();
        try (
            BufferedReader in  = new BufferedReader(new InputStreamReader(client.getInputStream(),  java.nio.charset.StandardCharsets.UTF_8));
            PrintWriter    out = new PrintWriter(new OutputStreamWriter(client.getOutputStream(), java.nio.charset.StandardCharsets.UTF_8), true)
        ) {
            String line;
            while ((line = in.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) continue;
                AtlasMain.log("TCP recv from " + remote + " : " + line.substring(0, Math.min(120, line.length())));
                String response = processMessage(line);
                out.println(response);
            }
        } catch (Exception e) {
            AtlasMain.log("Client " + remote + " error: " + e.getMessage());
        }
    }

    String processMessage(String rawJson) {
        try {
            ObjectNode msg = (ObjectNode) mapper.readTree(rawJson);

            String missionId  = msg.path("mission_id").asText("UNKNOWN");
            double confidence = msg.path("confidence").asDouble(0.0);
            String conclusion = msg.path("conclusion").asText("");

            // Classify priority
            String priority      = clf.classify(confidence, conclusion);
            String justification = clf.buildJustification(confidence, conclusion, priority);
            String agency        = registry.getAgency(missionId);

            msg.put("priority_level",       priority);
            msg.put("responsible_agency",   agency);
            msg.put("active_missions_count", registry.getActiveMissionsCount());

            // Append this node to traceability_chain
            ArrayNode chain = msg.withArrayProperty("traceability_chain");
            ObjectNode hop  = mapper.createObjectNode();
            hop.put("node",          "ATLAS");
            hop.put("timestamp_utc", Instant.now().toString());
            hop.put("action",        "ENRICH");
            chain.add(hop);

            AtlasMain.log("Enriched: mission=" + missionId + " priority=" + priority + " agency=" + agency);

            // Forward to GROUND with retry
            String enrichedJson = mapper.writeValueAsString(msg);
            forwardToGround(enrichedJson);

            return enrichedJson;

        } catch (Exception e) {
            AtlasMain.log("processMessage error: " + e.getMessage());
            return "{\"error\":\"" + e.getMessage().replace("\"", "'") + "\"}";
        }
    }

    private void forwardToGround(String json) {
        String groundUrl = System.getenv().getOrDefault("GROUND_URL", "http://localhost:5000") + "/api/events";
        int attempts = 0;
        while (attempts < 3) {
            try {
                java.net.URL url = new java.net.URL(groundUrl);
                java.net.HttpURLConnection conn = (java.net.HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
                conn.setDoOutput(true);
                conn.setConnectTimeout(5000);
                conn.setReadTimeout(10000);
                try (OutputStream os = conn.getOutputStream()) {
                    os.write(json.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                }
                int code = conn.getResponseCode();
                AtlasMain.log("GROUND responded HTTP " + code);
                if (code >= 200 && code < 300) return;
                AtlasMain.log("GROUND non-2xx, retrying...");
            } catch (Exception e) {
                AtlasMain.log("GROUND forward attempt " + (attempts + 1) + " failed: " + e.getMessage());
            }
            attempts++;
            try { Thread.sleep((long) Math.pow(2, attempts) * 500); } catch (InterruptedException ie) { break; }
        }
        AtlasMain.log("GROUND forward failed after 3 attempts — giving up");
    }
}
