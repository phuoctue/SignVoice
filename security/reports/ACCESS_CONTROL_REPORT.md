# ACCESS_CONTROL Security Report

## Status: MEDIUM

## Findings

Private route groups generally pass `req.user.id` into service calls (`conversation`, `history`, `favorites`, `users`, and sign collections). The audit did not exhaustively prove ownership checks for every ID-bearing handler, especially learning/quiz and staff report paths.

## What's at risk

An IDOR in a single service query could permit reading, editing, or deleting another user's data after valid authentication.

## What's already secure

Authentication and ownership are represented as separate concerns in the middleware/service APIs, and route schemas validate ObjectId-shaped identifiers.

## Recommendations

Complete a resource-by-resource matrix and add two-user negative tests for GET, PATCH, POST actions, and DELETE operations.
