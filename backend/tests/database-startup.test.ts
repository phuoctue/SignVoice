import {beforeEach,describe,expect,it,vi} from 'vitest';
import mongoose from 'mongoose';
import {connectDatabase} from '../src/config/database';

vi.mock('../src/config/env',()=>({env:{MONGODB_URI:'mongodb://127.0.0.1:27017/signvoice_test_startup'}}));
vi.mock('mongoose',()=>({default:{connect:vi.fn(),disconnect:vi.fn(),connection:{on:vi.fn(),name:'signvoice_test_startup',host:'127.0.0.1'}}}));
const selectionError=()=>Object.assign(new Error('Initial server selection timed out'),{name:'MongooseServerSelectionError'});
describe('Database startup recovery',()=>{
  beforeEach(()=>vi.resetAllMocks());
  it('allows a bounded cold handshake window and recovers from one selection failure',async()=>{
    vi.mocked(mongoose.connect).mockRejectedValueOnce(selectionError()).mockResolvedValueOnce(mongoose);
    await connectDatabase();
    expect(mongoose.connect).toHaveBeenCalledTimes(2);
    expect(mongoose.disconnect).toHaveBeenCalledOnce();
    for(const [,options] of vi.mocked(mongoose.connect).mock.calls)expect(options?.serverSelectionTimeoutMS).toBe(15000);
    expect(mongoose.connection.on).toHaveBeenCalledTimes(3);
  });
  it('bounds recovery to one retry and does not install listeners on failure',async()=>{
    const error=selectionError();vi.mocked(mongoose.connect).mockRejectedValue(error);
    await expect(connectDatabase()).rejects.toBe(error);
    expect(mongoose.connect).toHaveBeenCalledTimes(2);
    expect(mongoose.connection.on).not.toHaveBeenCalled();
  });
  it('fails authentication and configuration errors without retrying',async()=>{
    const error=Object.assign(new Error('Authentication failed'),{name:'MongoServerError',code:18});
    vi.mocked(mongoose.connect).mockRejectedValue(error);
    await expect(connectDatabase()).rejects.toBe(error);
    expect(mongoose.connect).toHaveBeenCalledOnce();
    expect(mongoose.disconnect).not.toHaveBeenCalled();
  });
});
