<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Lock Screen</title>
  <style>
    body {
      margin: 0;
      background: linear-gradient(#1b0034, #3f006f);
      color: white;
      font-family: Arial, sans-serif;
      text-align: center;
    }
    .time {
      font-size: 60px;
      margin-top: 40px;
    }
    .date {
      font-size: 20px;
      margin-bottom: 30px;
    }
    .unlock-button {
      padding: 12px 24px;
      background: #4a00e0;
      border: none;
      border-radius: 10px;
      color: white;
      font-size: 18px;
      cursor: pointer;
    }
  </style>
</head>
<body>
  <div class="time" id="time">--:--</div>
  <div class="date" id="date">--</div>

  <button class="unlock-button" onclick="unlock()">فتح القفل</button>

  <script>
    function unlock() {
      if (window.UnlockChannel) {
        UnlockChannel.postMessage("unlocked");
      }
    }

    function updateTime() {
      const now = new Date();
      document.getElementById("time").innerText =
        now.getHours().toString().padStart(2, '0') + ":" +
        now.getMinutes().toString().padStart(2, '0');

      document.getElementById("date").innerText =
        now.toLocaleDateString("ar-EG", { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
    }

    updateTime();
    setInterval(updateTime, 1000);
  </script>
</body>
</html>
