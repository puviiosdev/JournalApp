import { corsHeaders } from "jsr:@supabase/supabase-js@2/cors";

Deno.serve(async (req) => {
  // 1. Handle CORS preflight check
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 2. Main processing logic
  try {
    const { text } = await req.json();
    
    if (!text || typeof text !== "string") {
      throw new Error("Missing or invalid 'text' parameter in request body.");
    }

    // Simulate secure backend AI processing layer
    const lowerText = text.toLowerCase();
    let sentiment = "Neutral";
    let summary = "The journal entry reflects on standard daily experiences.";

    if (lowerText.includes("happy") || lowerText.includes("great") || lowerText.includes("love") || lowerText.includes("joy") || lowerText.includes("wonderful") || lowerText.includes("excited")) {
      sentiment = "Positive";
      summary = "The user is experiencing positive emotions, reflecting happiness, excitement, or appreciation for positive events.";
    } else if (lowerText.includes("sad") || lowerText.includes("angry") || lowerText.includes("bad") || lowerText.includes("hate") || lowerText.includes("disappointed") || lowerText.includes("tired")) {
      sentiment = "Negative";
      summary = "The user is venting or expressing challenging emotions, such as sadness, fatigue, or frustration.";
    }

    const data = {
      sentiment: sentiment,
      ai_summary: summary
    };

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    // 3. Return errors with CORS headers
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});
