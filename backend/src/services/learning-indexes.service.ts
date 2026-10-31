import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {ReviewQuiz} from '../models/ReviewQuiz.model';
import {SignCollection,SignNote,CollectionReport} from '../models/SignCollection.model';
import {PersonalWord} from '../models/Learning.model';

/** Create replacements before retiring only the exact legacy draft index. */
export async function ensureLearningIndexes() {
  await Promise.all([ReviewQuiz.init(),SignCollection.init(),SignNote.init(),PersonalWord.init(),CollectionReport.init()]);
  const indexes=await ReviewQuiz.collection.indexes();
  const legacy=indexes.find(index=>index.name==='userId_1_topicId_1' && index.unique===true &&
    JSON.stringify(index.key)===JSON.stringify({userId:1,topicId:1}) &&
    JSON.stringify(index.partialFilterExpression)===JSON.stringify({status:'DRAFT'}));
  if(!legacy)return;
  // init() has finished building both new unique indexes. Preserve recovery data.
  const folder=path.resolve(__dirname,'../../../.runtime');
  await mkdir(folder,{recursive:true});
  await writeFile(path.join(folder,`quiz-draft-index-backup-${Date.now()}.json`),JSON.stringify(legacy,null,2),{flag:'wx'});
  await ReviewQuiz.collection.dropIndex(legacy.name!);
}
