// app.js
const http = require("http");

const PORT = process.env.PORT || 8080;
const MESSAGE = process.env.MESSAGE || "Hello from Microservice";

const server = http.createServer((req, res) => {
  // Simple health check or any path
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end(MESSAGE + "\n");
});

server.listen(PORT, () => {
  console.log(`Microservice running on port ${PORT}`);
});
