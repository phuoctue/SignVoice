import { writeContent } from '../services/content-management.service';
import { Request, Response, NextFunction } from 'express';
import * as dictionaryService from '../services/dictionary.service';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';

/**
 * Get published dictionary entries
 * GET /api/v1/dictionary
 */
export async function getEntries(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const { categoryId, search, difficulty, limit, skip, sort } = req.query;
    
    const result = await dictionaryService.getPublishedEntries({
      categoryId: categoryId as string,
      search: search as string,
      difficulty: difficulty as string,
      sort: sort as 'word_asc' | 'word_desc' | undefined,
      limit: limit ? parseInt(limit as string) : undefined,
      skip: skip ? parseInt(skip as string) : undefined,
    });
    
    res.status(200).json({
      success: true,
      data: result.entries,
      pagination: {
        total: result.total,
        limit: limit ? parseInt(limit as string) : 20,
        skip: skip ? parseInt(skip as string) : 0,
      },
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Get dictionary entry by ID
 * GET /api/v1/dictionary/:id
 */
export async function getEntryById(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const { id } = req.params;
    const entry = await dictionaryService.getEntryById(id, req.user?.id);
    
    res.status(200).json({
      success: true,
      data: entry,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Get popular entries
 * GET /api/v1/dictionary/popular
 */
export async function getPopularEntries(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const { limit } = req.query;
    const entries = await dictionaryService.getPopularEntries(
      limit ? parseInt(limit as string) : undefined
    );
    
    res.status(200).json({
      success: true,
      data: entries,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Create draft entry (STAFF/ADMIN only)
 * POST /api/v1/dictionary
 */
export async function createEntry(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const entry = await writeContent(req.user!, {...req.body, status: 'DRAFT'});
    res.status(201).json({
      success: true,
      data: entry,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Update draft entry (STAFF/ADMIN only)
 * PATCH /api/v1/dictionary/:id
 */
export async function updateEntry(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const { id } = req.params;
    const entry = await writeContent(req.user!, req.body, id);
    res.status(200).json({
      success: true,
      data: entry,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Publish entry (ADMIN only)
 * POST /api/v1/dictionary/:id/publish
 */
export async function publishEntry(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const { id } = req.params;
    const entry = await writeContent(req.user!, {status:'PUBLISHED'}, id);
    
    res.status(200).json({
      success: true,
      data: entry,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Archive entry (ADMIN only)
 * POST /api/v1/dictionary/:id/archive
 */
export async function archiveEntry(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const { id } = req.params;
    const entry = await writeContent(req.user!, {status:'ARCHIVED'}, id);
    
    res.status(200).json({
      success: true,
      data: entry,
    });
  } catch (error) {
    next(error);
  }
}
