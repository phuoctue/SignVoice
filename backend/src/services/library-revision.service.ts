import {LibraryRevision} from '../models/LibraryRevision.model';
let cached:{revision:string;updatedAt:Date|null}|null=null,saved=0;
let pending:Promise<{revision:string;updatedAt:Date|null}>|undefined;
export function invalidateLibraryRevision(){cached=null;saved=0;}
export async function libraryRevision() {
  if(cached && Date.now()-saved<5000)return cached;
  if(pending)return pending;
  const request=(async()=>{
    const row=await LibraryRevision.findById('dictionary').lean();
    const result={revision:row?.revision || 'initial',updatedAt:row?.updatedAt || null};
    cached=result;saved=Date.now();return result;
  })();pending=request;
  try{return await request;}finally{if(pending===request)pending=undefined;}
}
