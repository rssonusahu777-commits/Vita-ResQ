const { GoogleGenAI } = require('@google/genai');
const config = require('../config');

/**
 * Gemini Service using the official Google Gen AI SDK (@google/genai).
 * 
 * Free-Tier Notice & Data Governance:
 * - Free-tier API calls are subject to rate/quota limits (e.g. RPM / RPD restrictions).
 * - Under Google's standard free-tier terms, data submitted in prompts may be processed
 *   by human reviewers and used to improve Google products.
 * - For this reason, strict sanitization MUST ALWAYS be performed prior to invoking this service.
 * - No exact GPS coordinates, personal victim/helper names, phone numbers, or tokens
 *   are ever passed into model prompts.
 * - No billable extras (grounding, Google Search tools, code execution) are enabled.
 */

let geminiClient = null;
let mockGeminiClient = null;

function getGeminiClient() {
  if (mockGeminiClient) return mockGeminiClient;
  if (!config.geminiApiKey) {
    const error = new Error('Gemini API key is not configured. Please set GEMINI_API_KEY in backend/.env');
    error.statusCode = 503;
    error.code = 'GEMINI_KEY_MISSING';
    throw error;
  }
  if (!geminiClient) {
    geminiClient = new GoogleGenAI({ apiKey: config.geminiApiKey });
  }
  return geminiClient;
}

/**
 * Injects a mock Gemini client for automated unit and integration testing.
 */
function setMockGeminiClient(client) {
  mockGeminiClient = client;
}

/**
 * Builds the strict, safety-focused system prompt for the assistant.
 */
function buildSystemPrompt(language = 'en') {
  const isHindi = language === 'hi';

  if (isHindi) {
    return `आप वीटा रेस्क्यू (Vita ResQ) आपातकालीन प्रतिक्रिया प्रणाली के एक सहयोगी और शांत AI सहायक हैं।
नियम:
1. केवल दी गई सत्यापित स्थिति और तथ्यों के आधार पर उत्तर दें।
2. कभी भी किसी नए स्वयंसेवक, दूरी, रूट, लक्षण या स्थिति का अनुमान या आविष्कार न करें।
3. कोई भी चिकित्सीय निदान (Medical Diagnosis) या उपचार की सलाह न दें।
4. हमेशा शांत, संक्षिप्त और स्पष्ट हिंदी में उत्तर दें (अधिकतम 3-4 वाक्य)।
5. आधिकारिक सरकारी आपातकालीन सहायता के लिए हमेशा 112 डायल करने की सलाह याद रखें।
6. यदि कोई जानकारी उपलब्ध नहीं है (जैसे GPS या ETA), तो स्पष्ट रूप से बताएं कि यह अभी उपलब्ध नहीं है।`;
  }

  return `You are a calm, concise, read-only AI Assistant for the Vita ResQ community emergency response app.
STRICT SAFETY AND PRIVACY RULES:
1. Base your explanations ONLY on the supplied verified facts and emergency status.
2. PRESERVE UNCERTAINTY: If an ETA, distance, or responder is missing or unavailable, clearly state that it is currently unavailable. Never guess, invent, or extrapolate.
3. NEVER PROVIDE MEDICAL DIAGNOSES OR TREATMENT RECOMMENDATIONS: If the user asks for medical advice, direct them to emergency personnel or official 112 services.
4. NO DATABASE ACTIONS: You are strictly informational. You cannot assign responders, cancel emergencies, change statuses, or update locations.
5. KEEP RESPONSES BRIEF AND CALM: Provide 2 to 4 clear, soothing, jargon-free sentences.
6. Vita ResQ connects nearby community volunteers and does not replace official 112 services. For life-threatening situations, 112 must be dialed.`;
}

/**
 * Calls Gemini to explain the emergency situation and answer responder/victim questions.
 */
async function generateAssistantResponse({ sanitizedContext, userQuery, language = 'en' }) {
  const client = getGeminiClient();
  const modelName = config.geminiModel;
  const systemInstruction = buildSystemPrompt(language);

  const prompt = `Current Verified Emergency Status:
- Emergency Type: ${sanitizedContext.emergencyType}
- Current Operational Status: ${sanitizedContext.status}
- User Perspective: ${sanitizedContext.callerPerspective}
- Elapsed Time: ${sanitizedContext.elapsedMinutes} minutes
- Nearby Responders Registered: ${sanitizedContext.responderCount}
- Has Primary Responder: ${sanitizedContext.hasAssignedResponder}
- Role Assigned: ${sanitizedContext.assignedResponderRole}
- Estimated Coarse Distance: ${sanitizedContext.coarseDistance}
- Road Route Available: ${sanitizedContext.roadRouteAvailable}
- ETA Details: ${sanitizedContext.etaText}

User Question: ${userQuery || (language === 'hi' ? 'वर्तमान स्थिति का संक्षिप्त विवरण दें।' : 'Please provide a calm brief on the current emergency status.')}`;

  // Execute with strict timeout
  const timeoutMs = config.aiRequestTimeoutMs;
  let timeoutId;
  const timeoutPromise = new Promise((_, reject) => {
    timeoutId = setTimeout(() => {
      const err = new Error(`Gemini request timed out after ${timeoutMs}ms.`);
      err.statusCode = 504;
      err.code = 'AI_TIMEOUT';
      reject(err);
    }, timeoutMs);
  });

  try {
    let apiCallPromise;
    if (client.models && typeof client.models.generateContent === 'function') {
      // Official @google/genai SDK format
      apiCallPromise = client.models.generateContent({
        model: modelName,
        contents: prompt,
        config: {
          systemInstruction,
          maxOutputTokens: 300,
          temperature: 0.2, // Low temperature for factual consistency
          thinkingConfig: {
            thinkingLevel: 'low',
          },
        },
      });
    } else if (typeof client.getGenerativeModel === 'function') {
      // Adaptor for test mocks
      const model = client.getGenerativeModel({
        model: modelName,
        systemInstruction,
        generationConfig: {
          maxOutputTokens: 300,
          temperature: 0.2,
          thinkingConfig: {
            thinkingLevel: 'low',
          },
        },
      });
      apiCallPromise = model.generateContent(prompt).then((res) => res.response || res);
    } else {
      throw new Error('Unsupported Gemini client interface.');
    }

    const result = await Promise.race([apiCallPromise, timeoutPromise]);
    clearTimeout(timeoutId);

    let text = '';
    if (result) {
      if (typeof result.text === 'function') {
        text = result.text().trim();
      } else if (typeof result.text === 'string') {
        text = result.text.trim();
      } else if (result.candidates && result.candidates[0]?.content?.parts?.[0]?.text) {
        text = result.candidates[0].content.parts[0].text.trim();
      }
    }

    if (!text) {
      const err = new Error('Received empty response from Gemini API.');
      err.statusCode = 502;
      err.code = 'AI_EMPTY_RESPONSE';
      throw err;
    }

    return {
      success: true,
      answer: text,
      disclaimer: language === 'hi'
        ? 'AI द्वारा उत्पन्न विवरण। यह आधिकारिक आपातकालीन निर्देशों की जगह नहीं लेता।'
        : 'AI-generated situation update based on verified app data. Does not replace official 112 emergency services.',
      language,
      model: modelName,
    };
  } catch (err) {
    clearTimeout(timeoutId);
    if (err.statusCode) throw err;

    // Check for HTTP 429 quota errors from Gemini API
    if (
      err.status === 429 ||
      (err.message && err.message.includes('429')) ||
      (err.message && err.message.includes('RESOURCE_EXHAUSTED'))
    ) {
      const rateErr = new Error('Gemini API quota exceeded or rate-limited. Please retry shortly.');
      rateErr.statusCode = 429;
      rateErr.code = 'GEMINI_RATE_LIMITED';
      throw rateErr;
    }

    const providerErr = new Error(`Gemini generation failed: ${err.message}`);
    providerErr.statusCode = 502;
    providerErr.code = 'AI_PROVIDER_ERROR';
    throw providerErr;
  }
}

/**
 * Calls Gemini to generate a concise, calming situation brief.
 */
async function generateEmergencyBrief({ sanitizedContext, language = 'en' }) {
  const defaultQuery = language === 'hi'
    ? 'वर्तमान आपातकालीन स्थिति और प्राथमिक प्रतिक्रियाकर्ता की प्रगति का 2 वाक्यों में शांत विवरण दें।'
    : 'Provide a concise, 2-sentence calming situation brief on the current responder status.';

  return generateAssistantResponse({
    sanitizedContext,
    userQuery: defaultQuery,
    language,
  });
}

/**
 * Calls Gemini to generate an objective, privacy-safe interpretation of verified aggregate operational statistics.
 *
 * Strict Rules:
 * - Operates on AGGREGATE statistics only (counts, percentages, average/median latencies, sample sizes).
 * - Zero PII, zero coordinates, zero SQL queries, and zero state mutation.
 * - Explicitly mentions sample sizes and time window.
 * - Distinguishes correlation from causation and highlights data gaps.
 */
async function generateAnalyticsInsights({ sanitizedSummary, focusArea = 'general', language = 'en' }) {
  if (!sanitizedSummary || !sanitizedSummary.sufficientData) {
    return {
      success: true,
      available: false,
      reason: 'INSUFFICIENT_DATA',
      message: 'Insufficient historical analytics data recorded to date to generate reliable AI insights.',
      insights: null,
    };
  }

  const client = getGeminiClient();
  const modelName = config.geminiModel;

  const systemInstruction = `You are an expert, objective operational performance analyst for the Vita ResQ community emergency response system.
STRICT ANALYSIS & SAFETY RULES:
1. Base all observations and insights EXCLUSIVELY on the verified aggregate metrics provided below.
2. NEVER invent, hallucinate, or extrapolate metrics not present in the data.
3. Explicitly cite sample sizes (e.g. N=X) and the reporting time window when discussing metrics.
4. Distinguish correlation from causation (e.g., offline delays may be due to local mesh connectivity conditions rather than responder speed).
5. If a metric is sparse, low sample size, or marked N/A, clearly state that data is insufficient for a definitive conclusion.
6. Provide actionable operational suggestions for HUMAN review only. Never suggest automated or unilateral changes to emergency dispatch rules.
7. Keep your response concise (under 250 words), clear, and organized into bullet points.`;

  const life = sanitizedSummary.lifecycle || {};
  const resp = sanitizedSummary.responseTimes || {};
  const rout = sanitizedSummary.routing || {};
  const sync = sanitizedSummary.offlineSync || {};
  const tw = sanitizedSummary.timeWindow || {};

  const prompt = `Verified Aggregate Operational Performance Data:
- Reporting Window: ${tw.from || 'Start'} to ${tw.to || 'Now'}
- Total Emergencies Created: ${life.totalEmergencies || 0}
  * Completed: ${life.completed || 0} (${life.completionRatePercent || 0}%)
  * Cancelled: ${life.cancelled || 0}
  * Offline-Initiated: ${life.offlineInitiated || 0}
- Response Time to First Responder Acceptance:
  * Sample Size: N=${resp.timeToAcceptance?.sampleCount || 0}
  * Average: ${resp.timeToAcceptance?.avgSeconds !== null ? resp.timeToAcceptance?.avgSeconds + 's' : 'N/A'}
  * Median: ${resp.timeToAcceptance?.medianSeconds !== null ? resp.timeToAcceptance?.medianSeconds + 's' : 'N/A'}
- Response Time to Scene Arrival:
  * Sample Size: N=${resp.timeToArrival?.sampleCount || 0}
  * Average: ${resp.timeToArrival?.avgSeconds !== null ? resp.timeToArrival?.avgSeconds + 's' : 'N/A'}
  * Median: ${resp.timeToArrival?.medianSeconds !== null ? resp.timeToArrival?.medianSeconds + 's' : 'N/A'}
- Average Total Emergency Duration: ${resp.avgTotalDurationSeconds !== null ? resp.avgTotalDurationSeconds + 's' : 'N/A'}
- Navigation Routing Reliability:
  * Total Requests: ${rout.totalRequests || 0}
  * Success Rate: ${rout.successRatePercent !== null ? rout.successRatePercent + '%' : 'N/A'}
  * Average Latency: ${rout.avgLatencyMs !== null ? rout.avgLatencyMs + 'ms' : 'N/A'}
- Offline Synchronization Reliability:
  * Total Sync Attempts: ${sync.totalSyncAttempts || 0}
  * Sync Success Rate: ${sync.successRatePercent !== null ? sync.successRatePercent + '%' : 'N/A'}
  * Average Sync Latency: ${sync.avgSyncLatencyMs !== null ? sync.avgSyncLatencyMs + 'ms' : 'N/A'}
  * Average Retries: ${sync.avgRetryCount !== null ? sync.avgRetryCount : 'N/A'}

Analysis Focus Area: ${focusArea}

Please provide an objective, data-grounded performance summary and key operational observations for emergency operations administrators.`;

  const timeoutMs = config.aiRequestTimeoutMs || 8000;
  let timeoutId;
  const timeoutPromise = new Promise((_, reject) => {
    timeoutId = setTimeout(() => {
      const err = new Error(`Gemini request timed out after ${timeoutMs}ms.`);
      err.statusCode = 504;
      err.code = 'AI_TIMEOUT';
      reject(err);
    }, timeoutMs);
  });

  try {
    const apiPromise = client.models.generateContent({
      model: modelName,
      contents: prompt,
      config: {
        systemInstruction,
        temperature: 0.2, // Low temperature for factual, analytical consistency
        thinkingConfig: {
          thinkingLevel: 'low',
        },
      },
    });

    const response = await Promise.race([apiPromise, timeoutPromise]);
    clearTimeout(timeoutId);

    const text = response && response.text && response.text.trim();
    if (!text) {
      const emptyErr = new Error('Empty response received from AI model provider.');
      emptyErr.statusCode = 502;
      emptyErr.code = 'AI_EMPTY_RESPONSE';
      throw emptyErr;
    }

    return {
      success: true,
      available: true,
      timeWindow: tw,
      sampleSize: life.totalEmergencies || 0,
      insights: text,
      disclaimer: 'AI-generated operational interpretation derived strictly from aggregate metrics. Not an automated system change.',
      generatedAt: new Date().toISOString(),
      model: modelName,
    };
  } catch (err) {
    clearTimeout(timeoutId);
    if (err.statusCode) throw err;

    if (
      err.status === 429 ||
      (err.message && err.message.includes('429')) ||
      (err.message && err.message.includes('RESOURCE_EXHAUSTED'))
    ) {
      const rateErr = new Error('Gemini API quota exceeded or rate-limited. Please retry shortly.');
      rateErr.statusCode = 429;
      rateErr.code = 'GEMINI_RATE_LIMITED';
      throw rateErr;
    }

    const providerErr = new Error(`Gemini insight generation failed: ${err.message}`);
    providerErr.statusCode = 502;
    providerErr.code = 'AI_PROVIDER_ERROR';
    throw providerErr;
  }
}

module.exports = {
  getGeminiClient,
  setMockGeminiClient,
  buildSystemPrompt,
  generateAssistantResponse,
  generateEmergencyBrief,
  generateAnalyticsInsights,
};
