import {Types} from 'mongoose';

/** Private registry hookup is deferred to K+S/task 5; the default grants no cleanup exemption. */
export const syntheticCanaryRegistry = {
  contains: async (userId: Types.ObjectId): Promise<boolean | undefined> => {void userId; return false;},
};

export async function isSyntheticCanary(userId: Types.ObjectId): Promise<boolean> {
  try { return await syntheticCanaryRegistry.contains(userId) === true; }
  catch { return false; }
}
