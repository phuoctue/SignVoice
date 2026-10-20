import { Router, Request, Response } from 'express';

const router = Router();
const LM_STUDIO_URL = process.env.LM_STUDIO_URL || 'http://127.0.0.1:1234/v1';

/**
 * GET /api/v1/ai/models
 * Proxy to LM Studio models endpoint
 */
router.get('/models', async (_req: Request, res: Response) => {
  try {
    const response = await fetch(`${LM_STUDIO_URL}/models`, {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) {
      const errorText = await response.text();
      return res.status(response.status).json({
        success: false,
        error: { code: 'AI_SERVER_ERROR', message: errorText },
      });
    }

    const data = await response.json();
    return res.status(200).json(data);
  } catch (error) {
    return res.status(502).json({
      success: false,
      error: {
        code: 'LM_STUDIO_UNREACHABLE',
        message: error instanceof Error ? error.message : 'Cannot connect to LM Studio',
      },
    });
  }
});

/**
 * POST /api/v1/ai/chat/completions
 * Proxy to LM Studio chat completions endpoint (supports vision with base64)
 */
router.post('/chat/completions', async (req: Request, res: Response) => {
  try {
    const response = await fetch(`${LM_STUDIO_URL}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
      signal: AbortSignal.timeout(300000), // 5 min timeout for vision
    });

    if (!response.ok) {
      const errorText = await response.text();
      return res.status(response.status).json({
        success: false,
        error: { code: 'AI_CHAT_ERROR', message: errorText },
      });
    }

    const data = await response.json();
    return res.status(200).json(data);
  } catch (error) {
    return res.status(502).json({
      success: false,
      error: {
        code: 'LM_STUDIO_UNREACHABLE',
        message: error instanceof Error ? error.message : 'Failed to call LM Studio',
      },
    });
  }
});

export default router;
