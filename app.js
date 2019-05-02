var express = require('express');
var app = express();

app.get('/hello-bricks', function (req, res) {
  res.send('Hello bricks!');
});

app.listen(3000, function () {
});

