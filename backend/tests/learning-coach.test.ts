import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Types } from 'mongoose';
import { TopicEnrollment, WordProgress } from '../src/models/Learning.model';
import { DictionaryEntry } from '../src/models/DictionaryEntry.model';
import { Category } from '../src/models/Category.model';
import { enrolledTopics } from '../src/services/learning.service';
import { learningAdvice } from '../src/services/learning-coach.service';

vi.mock('../src/services/learning.service', () => ({ enrolledTopics: vi.fn() }));
const userId = new Types.ObjectId();
const topicId = new Types.ObjectId();
const summary = { total: 4, learning: 2, remembered: 1, review: 1 };
const words = [{ word: 'Xin chào', definition: 'Lời chào', usageExample: 'Xin chào bạn.' }];
function query(result: unknown) {
  const chain = { select: vi.fn(), sort: vi.fn(), limit: vi.fn(), lean: vi.fn().mockResolvedValue(result) };
  for (const key of ['select', 'sort', 'limit'] as const) chain[key].mockReturnValue(chain);
  return chain;
}
function response(content: unknown = 'Bạn đã nhớ 1 trong 4 từ. Hãy ôn nhóm còn yếu.', finish_reason = 'stop') {
  return new Response(JSON.stringify({ choices: [{ finish_reason, message: { content } }] }), { status: 200 });
}

beforeEach(() => {
  for (const key of ['SIGNVOICE_LM_STUDIO_URL', 'SIGNVOICE_LM_STUDIO_MODEL', 'SIGNVOICE_LM_STUDIO_API_KEY',
    'LM_STUDIO_URL', 'LM_STUDIO_MODEL', 'LM_STUDIO_API_KEY']) vi.stubEnv(key, '');
  vi.mocked(enrolledTopics).mockResolvedValue({ items: [], summary, pagination: { page: 1, pageSize: 10, total: 1, pages: 1 } });
  vi.spyOn(TopicEnrollment, 'find').mockReturnValue(query([{ topicId }]) as never);
  vi.spyOn(WordProgress, 'find').mockReturnValue(query([]) as never);
  vi.spyOn(Category, 'find').mockReturnValue(query([{ _id: topicId }]) as never);
  vi.spyOn(DictionaryEntry, 'find').mockReturnValue(query(words) as never);
});
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllEnvs(); vi.unstubAllGlobals(); });

describe('SignVoice coach connection', () => {
  it('uses the dedicated server/model/key without changing another project configuration', async () => {
    vi.stubEnv('SIGNVOICE_LM_STUDIO_URL', 'http://192.168.1.10:1235/v1/');
    vi.stubEnv('SIGNVOICE_LM_STUDIO_MODEL', 'signvoice-qwen');
    vi.stubEnv('SIGNVOICE_LM_STUDIO_API_KEY', 'private-test-key');
    vi.stubEnv('LM_STUDIO_URL', 'http://leaf-project:1234/v1');
    vi.stubEnv('LM_STUDIO_MODEL', 'leaf-vision');
    const fetchMock = vi.fn().mockResolvedValue(response());
    vi.stubGlobal('fetch', fetchMock);
    expect((await learningAdvice(userId)).source).toBe('lm-studio');
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe('http://192.168.1.10:1235/v1/chat/completions');
    expect(options.headers.Authorization).toBe('Bearer private-test-key');
    const payload = JSON.parse(options.body);
    expect(payload.model).toBe('signvoice-qwen');
    expect(JSON.parse(payload.messages[1].content)).toEqual({ summary, words });
    expect(process.env.LM_STUDIO_MODEL).toBe('leaf-vision');
  });

  it('defaults to port 1235 and Qwen3 rather than selecting the first listed model', async () => {
    const fetchMock = vi.fn().mockResolvedValue(response());
    vi.stubGlobal('fetch', fetchMock);
    expect((await learningAdvice(userId)).source).toBe('lm-studio');
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][0]).toBe('http://127.0.0.1:1235/v1/chat/completions');
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).model).toBe('qwen3-4b-instruct-2507');
  });

  it('allows a real 45 second model response without falling back after 20 seconds', async () => {
    vi.stubEnv('SIGNVOICE_LM_STUDIO_MODEL', 'test');
    vi.stubEnv('LM_STUDIO_MODEL', 'test');
    vi.useFakeTimers();
    vi.stubGlobal('fetch', vi.fn((_url, options) => new Promise((resolve, reject) => {
      const timer = setTimeout(() => resolve(response()), 45000);
      options.signal.addEventListener('abort', () => { clearTimeout(timer); reject(new Error('timeout')); });
    })));
    const signalTimeout = vi.spyOn(AbortSignal, 'timeout').mockImplementation(ms => {
      const controller = new AbortController();
      setTimeout(() => controller.abort(), ms);
      return controller.signal;
    });
    const result = learningAdvice(userId);
    await vi.advanceTimersByTimeAsync(45000);
    expect((await result).source).toBe('lm-studio');
    expect(signalTimeout).toHaveBeenCalled();
  });

  it.each([[null, 'stop'], [' ', 'stop'], [{ text: 'wrong shape' }, 'stop'], ['Incomplete answer', 'length']])(
    'uses a truthful rules fallback for invalid or truncated responses (%j, %s)', async (content, reason) => {
      vi.stubEnv('SIGNVOICE_LM_STUDIO_MODEL', 'test');
      vi.stubEnv('LM_STUDIO_MODEL', 'test');
      vi.stubGlobal('fetch', vi.fn().mockResolvedValue(response(content, reason as string)));
      const result = await learningAdvice(userId);
      expect(result.source).toBe('rules');
      expect(result.summary).toEqual(summary);
    },
  );

  it('does not call the model when there are no words to analyze', async () => {
    vi.mocked(DictionaryEntry.find).mockReturnValue(query([]) as never);
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    expect((await learningAdvice(userId)).source).toBe('rules');
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
