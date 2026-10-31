import {Router} from 'express';
import {libraryRevision} from '../services/library-revision.service';
const router=Router();
router.get('/version',async(_req,res,next)=>{
  try{res.setHeader('Cache-Control','no-store');res.json({success:true,data:await libraryRevision()});}catch(error){next(error);}
});
export default router;
