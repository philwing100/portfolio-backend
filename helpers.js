//helpers.js
function getTodayDate() {
    const today = new Date();
    const year = today.getFullYear();
    const month = (today.getMonth() + 1).toString().padStart(2, "0");
    const day = today.getDate().toString().padStart(2, "0");
    return `${year}-${month}-${day}`; // Format: YYYY-MM-DD
}

function normalizeDate(datetimeString) {
    // Create a Date object from the MySQL DATETIME string
    const date = new Date(datetimeString);

    // Extract year, month, and day and format them as YYYY-MM-DD
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');  // Month is 0-indexed, so +1
    const day = String(date.getDate()).padStart(2, '0');

    // Return the formatted date
    return `${year}-${month}-${day}`;
}

function getWeekDayFromDate(datetimeString) {
  const date = new Date(datetimeString);
  const weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",];
  return weekdays[date.getDay()];
}

module.exports = { getTodayDate, normalizeDate, getWeekDayFromDate };