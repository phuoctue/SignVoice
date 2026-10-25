import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Types } from 'mongoose';
import { TopicEnrollment } from '../src/models/Learning.model';
import { analyzeLearningProgress } from '../src/services/learning-analysis.service';

const snapshot = {
  summary: [{ total: 22, learning: 19, remembered: 1, review: 2, topicCount: 11 }],
  topics: [{ name: 'Chào hỏi', total: 2, learning: 0, remembered: 1, review: 1, rememberedPercent: 50 }],
};
beforeEach(() => {
  vi.spyOn(TopicEnrollment, 'aggregate').mockResolvedValue([snapshot]);
  vi.stubEnv('SIGNVOICE_LM_STUDIO_URL', 'http://192.168.1.10:1235/v1/');
  vi.stubEnv('SIGNVOICE_LM_STUDIO_MODEL', 'signvoice-qwen');
  vi.stubEnv('SIGNVOICE_LM_STUDIO_API_KEY', 'test-analysis-key');
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
const reply = (content: unknown, finish_reason = 'stop') => new Response(JSON.stringify({ choices: [{ message: { content }, finish_reason }] }));

describe('Personal learning analysis', () => {
  it('analyzes the snapshot with the dedicated model without exposing the account ID', async () => {
    const fetchMock = vi.fn().mockResolvedValue(reply('Bạn đã ghi nhận nhớ 1 trên 22 từ. Ưu tiên ổn định các chủ đề cần ôn.'));
    vi.stubGlobal('fetch', fetchMock);
    const userId = new Types.ObjectId();
    const result = await analyzeLearningProgress(userId);
    expect(result.source).toBe('lm-studio');
    expect(result.summary).toMatchObject({ total: 22, topicCount: 11, rememberedPercent: 5 });
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe('http://192.168.1.10:1235/v1/chat/completions');
    expect(options.headers.Authorization).toBe('Bearer test-analysis-key');
    const body = JSON.parse(options.body);
    expect(body.model).toBe('signvoice-qwen');
    const data = JSON.parse(body.messages[1].content);
    expect(data.summary.total).toBe(22);
    expect(data.topics[0].name).toBe('Chào hỏi');
    expect(options.body).not.toContain(String(userId));
  });

  it.each([[null, 'stop'], [' ', 'stop'], ['unfinished', 'length']])('keeps the snapshot with a rules label for invalid AI (%j, %s)', async (content, reason) => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(reply(content, reason as string)));
    const result = await analyzeLearningProgress(new Types.ObjectId());
    expect(result.source).toBe('rules');
    expect(result.summary).toMatchObject({ total: 22, learning: 19, remembered: 1, review: 2 });
    expect(result.analysis).toContain('22');
  });

  it('keeps deterministic analysis if the AI server is offline', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('offline')));
    expect((await analyzeLearningProgress(new Types.ObjectId())).source).toBe('rules');
  });

  it('does not contact AI with no started topics', async () => {
    vi.mocked(TopicEnrollment.aggregate).mockResolvedValue([{ summary: [], topics: [] }]);
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const result = await analyzeLearningProgress(new Types.ObjectId());
    expect(result.source).toBe('no-data');
    expect(result.summary).toMatchObject({ total: 0, rememberedPercent: 0, topicCount: 0 });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
