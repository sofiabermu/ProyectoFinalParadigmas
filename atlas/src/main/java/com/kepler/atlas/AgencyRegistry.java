package com.kepler.atlas;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Maps mission_id prefixes to responsible agencies.
 * Also holds the active-missions counter (pre-loaded with 140 entries).
 */
public class AgencyRegistry {

    private final Map<String, String> missionAgency = new ConcurrentHashMap<>();
    private final Map<String, String> activeMissions = new ConcurrentHashMap<>();

    public AgencyRegistry() {
        // Known missions from seed + demo
        missionAgency.put("VOY-IX-KEPLER442",  "NASA");
        missionAgency.put("VOY-VII-TRAPPIST1", "ESA");
        missionAgency.put("VOY-VIII-PROXIMA",  "JAXA");

        // Pre-load 140 simulated active missions
        String[] agencies = {
            "NASA","ESA","JAXA","CNSA","ISRO","ROSCOSMOS","CSA","KARI",
            "CNES","DLR","ASI","UKSA","UAE-SA","INPE","SNSB","NCSIST"
        };
        for (int i = 1; i <= 140; i++) {
            String id  = String.format("SIM-%03d", i);
            String ag  = agencies[i % agencies.length];
            activeMissions.put(id, ag);
            missionAgency.put(id, ag);
        }
    }

    public String getAgency(String missionId) {
        // Exact match first, then prefix scan
        if (missionAgency.containsKey(missionId)) {
            return missionAgency.get(missionId);
        }
        for (Map.Entry<String, String> e : missionAgency.entrySet()) {
            if (missionId.startsWith(e.getKey())) {
                return e.getValue();
            }
        }
        return "UNKNOWN";
    }

    public int getActiveMissionsCount() {
        return activeMissions.size();
    }

    public Map<String, String> getActiveMissions() {
        return activeMissions;
    }
}
