package com.kepler.atlas;

/**
 * Classifies observation priority.
 * PRIORITY_MAX: confidence >= 0.85 AND conclusion contains "no natural"
 * PRIORITY_HIGH: confidence >= 0.75
 * PRIORITY_MEDIUM: confidence >= 0.55
 * PRIORITY_LOW: everything else
 */
public class PriorityClassifier {

    public String classify(double confidence, String conclusion) {
        String lower = conclusion == null ? "" : conclusion.toLowerCase();
        boolean isUnnatural = lower.contains("no natural")
                           || lower.contains("unnatural")
                           || lower.contains("no nat");

        if (confidence >= 0.85 && isUnnatural) return "PRIORITY_MAX";
        if (confidence >= 0.85)                return "PRIORITY_HIGH";
        if (confidence >= 0.75)                return "PRIORITY_HIGH";
        if (confidence >= 0.55)                return "PRIORITY_MEDIUM";
        return "PRIORITY_LOW";
    }

    public String buildJustification(double confidence, String conclusion, String priority) {
        return String.format("confidence=%.2f conclusion='%s' -> %s", confidence, conclusion, priority);
    }
}
