process.env.PORT = '3001';
process.env.SERVE_WEB = 'true';
process.env.NODE_ENV = 'production';
// Supply PUBLIC_ORIGIN from your own tunnel; never reuse another machine's URL.
process.env.PUBLIC_ORIGIN ||= 'http://localhost:3001';

const { startServer } = require('./dist/server.js');
startServer();
