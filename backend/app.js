// Express backend to receive MQTT messages and store them in PostgreSQL.
// Exposes Prometheus metrics on /metrics endpoint.

const express = require('express');
const promClient = require('prom-client');
const mqtt = require('mqtt');
const { Pool } = require('pg');

const app = express();
const port = process.env.PORT || 3000;

// Prometheus metrics
const mqttMessagesCounter = new promClient.Counter({
  name: 'mqtt_messages_total',
  help: 'Total number of MQTT messages received'
});
const dbInsertCounter = new promClient.Counter({
  name: 'db_inserts_total',
  help: 'Total number of DB inserts'
});

// PostgreSQL connection pool
const dbHost = process.env.DB_HOST || 'db';
const [dbHostname, dbPort] = dbHost.includes(':') ? dbHost.split(':') : [dbHost, '5432'];

// Function to get database password
async function getDbPassword() {
  if (process.env.DB_SECRET_ARN) {
    // Get password from AWS Secrets Manager
    const AWS = require('aws-sdk');
    const secretsManager = new AWS.SecretsManager({ region: process.env.AWS_REGION || 'eu-west-1' });

    try {
      const result = await secretsManager.getSecretValue({ SecretId: process.env.DB_SECRET_ARN }).promise();
      const secret = JSON.parse(result.SecretString);
      return secret.password;
    } catch (err) {
      console.error('Failed to get password from Secrets Manager:', err);
      return process.env.DB_PASSWORD || 'iotpassword';
    }
  }
  return process.env.DB_PASSWORD || 'iotpassword';
}

// Initialize pool with password from Secrets Manager
let pool;
getDbPassword().then(password => {
  // Check if this is AWS environment (has RDS endpoint)
  const isAWS = dbHostname.includes('.rds.amazonaws.com');

  pool = new Pool({
    host: dbHostname,
    user: process.env.DB_USER || 'iotuser',
    password: password,
    database: process.env.DB_NAME || 'iotdb',
    port: parseInt(dbPort),
    // Enable SSL for AWS RDS
    ssl: isAWS ? { rejectUnauthorized: false } : false
  });

  // Test database connection after pool is created
  testDatabaseConnection();
}).catch(err => {
  console.error('Failed to initialize database pool:', err);
  // Fallback to default pool
  pool = new Pool({
    host: dbHostname,
    user: process.env.DB_USER || 'iotuser',
    password: 'iotpassword',
    database: process.env.DB_NAME || 'iotdb',
    port: parseInt(dbPort),
    ssl: false
  });
});

// Function to test database connection
function testDatabaseConnection() {
  if (!pool) {
    console.log('Database pool not initialized yet');
    return;
  }

  pool.connect()
    .then(client => {
      console.log(`Connected to PostgreSQL database at ${dbHostname}:${dbPort}`);

      // Create messages table if it doesn't exist
      client.query(`
        CREATE TABLE IF NOT EXISTS messages (
          id SERIAL PRIMARY KEY,
          payload TEXT NOT NULL,
          timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `)
        .then(() => {
          console.log('Messages table ready');
          client.release();
        })
        .catch(err => {
          console.error('Table creation error:', err);
          client.release();
        });
    })
    .catch(err => {
      console.error('Database connection error:', err);
    });
}

// MQTT client connection - environment specific
const mqttHost = process.env.MQTT_HOST || 'mqtt';
let mqttClient;

// Check if MQTT_HOST is an AWS IoT Core endpoint
if (mqttHost.includes('.iot.') && mqttHost.includes('.amazonaws.com')) {
  // AWS IoT Core MQTT connection using WebSocket + IRSA
  console.log(`Connecting to AWS IoT Core: ${mqttHost}`);

  const AWS = require('aws-sdk');
  const awsIot = require('aws-iot-device-sdk');

  // Get credentials from IRSA
  const credentials = new AWS.CredentialProviderChain().resolvePromise()
    .then(creds => {
      console.log('AWS credentials resolved successfully');

      // Use WebSocket connection with explicit credentials
      mqttClient = awsIot.device({
        protocol: 'wss',
        host: mqttHost,
        region: process.env.AWS_REGION || 'eu-west-1',
        clientId: 'iot-backend-' + Math.random().toString(36).substr(2, 9),
        accessKeyId: creds.accessKeyId,
        secretKey: creds.secretAccessKey,
        sessionToken: creds.sessionToken
      });

      // Set up MQTT handlers
      setupMqttHandlers();
    })
    .catch(err => {
      console.error('Failed to resolve AWS credentials:', err);
      // Create mock client to prevent crashes
      mqttClient = { on: () => { }, subscribe: () => { } };
    });

  // Create temporary mock client until credentials are resolved
  mqttClient = { on: () => { }, subscribe: () => { } };
} else {
  // Local Mosquitto connection
  console.log(`Connecting to local MQTT broker: ${mqttHost}`);
  mqttClient = mqtt.connect(`mqtt://${mqttHost}:1883`);
}

// Function to set up MQTT handlers
function setupMqttHandlers() {
  if (!mqttClient || typeof mqttClient.on !== 'function') return;

  mqttClient.on('connect', () => {
    console.log('Connected to MQTT broker');
    mqttClient.subscribe('iot/data', (err) => {
      if (err) console.error('MQTT subscription error:', err);
      else console.log('Subscribed to topic iot/data');
    });
  });

  mqttClient.on('message', async (topic, message) => {
    const payload = message.toString();
    console.log(`Received MQTT message: ${payload}`);
    mqttMessagesCounter.inc();

    try {
      await pool.query('INSERT INTO messages(payload) VALUES($1)', [payload]);
      dbInsertCounter.inc();
    } catch (err) {
      console.error('Database insert error:', err);
    }
  });
}

// Set up MQTT handlers for non-AWS environments
if (!mqttHost.includes('.iot.') || !mqttHost.includes('.amazonaws.com')) {
  setupMqttHandlers();
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.use(express.json());

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', promClient.register.contentType);
  res.end(await promClient.register.metrics());
});

app.listen(port, () => {
  console.log(`Backend service running on port ${port}`);
});

// test deploy