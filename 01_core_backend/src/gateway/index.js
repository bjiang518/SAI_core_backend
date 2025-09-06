const fastify = require('fastify')({ logger: true });
const axios = require('axios');

const AI_ENGINE_URL = process.env.AI_ENGINE_URL || 'http://localhost:8000';

// Health check endpoint
fastify.get('/health', async (request, reply) => {
  return { status: 'ok', service: 'api-gateway' };
});

// AI Engine proxy
fastify.all('/api/ai/*', async (request, reply) => {
  const servicePath = request.url.replace('/api/ai', '');
  try {
    const response = await axios({
      method: request.method,
      url: `${AI_ENGINE_URL}${servicePath}`,
      data: request.body,
      headers: {
        // Forward any important headers
        'Content-Type': request.headers['content-type'],
      },
    });
    reply.send(response.data);
  } catch (error) {
    fastify.log.error(error);
    reply.status(500).send({ error: 'Error connecting to the AI Engine' });
  }
});

const start = async () => {
  try {
    await fastify.listen({ port: 4000 });
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();