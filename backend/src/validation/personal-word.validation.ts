import {z} from 'zod';
const safeMedia=(value:string)=>{
  if(!value)return true;
  try{const url=new URL(value);return url.protocol==='https:' && !url.username && !url.password;}catch{return false;}
};
export const personalWordSchema=z.object({
  word:z.string().trim().min(1).max(100),
  definition:z.string().trim().min(1).max(2000),
  usageExample:z.string().trim().max(1000).default(''),
  notes:z.string().trim().max(2000).default(''),
  imageUrl:z.string().max(1500000).default('').refine(value=>safeMedia(value)||/^data:image\/(?:jpeg|png|webp);base64,[A-Za-z0-9+/]+=*$/.test(value)),
  videoUrl:z.string().max(2000).default('').refine(safeMedia),
}).strict();
