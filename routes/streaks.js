const express = require('express');
const jwt = require('jsonwebtoken');
const pool = require('../databaseConnection/database');
const auth = require('./auth');
const router = express.Router();
const { getTodayDate, normalizeDate } = require('../helpers');

const getStreaks = async function getStreaks(req, res) {
    try {
        const userId = req.user.id;

        if (userId) {
            const { rows: streaks } = await pool.query(
                'SELECT * FROM fetch_streaks($1)',
                [userId]
            );
            if (streaks?.length > 0) {
                console.log(streaks);
                let resetIDs = [];
                for (const streak of streaks) {
                    let temp = CheckForStreakReset(streak);
                    if (temp !== null) {
                        resetIDs.push(temp);
                    }
                }

                // If we have streaks to reset, call the stored procedure
                if (resetIDs.length > 0) {
                    const streakIDsString = resetIDs.join(',');
                    await pool.query('SELECT reset_streaks_by_ids($1, $2)',
                        [userId, streakIDsString]
                    );

                    // Fetch updated streaks
                    const { rows: updatedStreaks } = await pool.query(
                        'SELECT * FROM fetch_streaks($1)',
                        [userId]
                    );
                    return res.json({ success: true, data: updatedStreaks });
                }

                return res.json({ success: true, data: streaks });
            } else {
                return res.json({ success: true, message: "No streaks found for this user" });
            }
        } else {
            return res.status(400).json({ message: 'User not authenticated' });
        }
    } catch (error) {
        console.error("Error fetching streaks:", error);
        return res.status(500).json({ success: false, error: "Server error" });
    }
};

function CheckForStreakReset(streak) {
       let prev = new Date(normalizeDate(streak.last_updated));
    let curr = new Date(getTodayDate());

    // Convert milliseconds to days
    const daysDifference = Math.floor((curr - prev) / (1000 * 60 * 60 * 24));
    //console.log('days difference: ' + daysDifference);
    if (daysDifference > 7) {
        console.log(`Days difference: ${daysDifference}, resetting streak: ${streak.streak_id}`);
        return streak.streak_id;
    }
    let pdotw = (prev.getDay() + 6) % 7; //Need the index of the day of the week.
    let cdotw = (curr.getDay() + 6) %7;
    let days = streak.days.toString(2) + "";
    days = days + days;
    //console.log('Days pattern:', days);
    //console.log('Day of week:', pdotw);
    for (let i = cdotw + 6; i > pdotw+6; i--) { //Start on the day and count backwards
    //     console.log('dec ' + (days.substring(pdotw+1,i+1)));
        if (days.substring(i,i+1) != 1) {
     //       console.log("returning, streak broken: " + streak.streak_id);
            return streak.streak_id;
        }
    }
  //  console.log("Passed: " + streak.streak_id );
    return null;
}

const incrementStreak = async (req, res) => {
    try {
        //Still doesn't do anything if the
        const userId = req.user.id;
        const parsed = JSON.parse(req.body.data);
        const {
            id: streakID
        } = parsed;

        if (userId && streakID != null) {
            const { rows } = await pool.query('SELECT * FROM increment_streak($1, $2)', [streakID, userId]);

            const affectedRows = rows?.[0]?.affected_rows;
            if (affectedRows > 0) {
                return res.json({ success: true, message: 'Streak incremented.' });
            } else {
                return res.json({ success: false, message: 'Streak already updated today.' });
            }
        } else {
            return res.status(400).json({ success: false, message: 'Missing streakID or user not authenticated' });
        }
    } catch (error) {
        console.error("Error incrementing streak:", error);
        return res.status(500).json({ success: false, error: "Server error" });
    }
};


const updateStreak = async (req, res) => {
    try {
        const userId = req.user.id;

        // Parse and extract the values
        const parsed = JSON.parse(req.body.data);
        const {
            id, title, notes, goal,
            tag, days, lastUpdated, color
        } = parsed.updatedHabit;

        //console.log("full object:", parsed.updatedHabit);

        if (userId && id != null) {
            await pool.query('SELECT update_streak($1, $2, $3, $4, $5, $6, $7, $8, $9)', [
                id, userId, title, notes, goal, tag, days, lastUpdated, color
            ]);
            return res.json({ success: true });
        } else {
            return res.status(400).json({ message: 'Missing streakID or user not authenticated' });
        }
    } catch (error) {
        console.error("Error updating streak:", error);
        return res.status(500).json({ success: false, error: "Server error" });
    }
};

const deleteStreak = async (req, res) => {
    try {
        const userId = req.user.id;
        const parsed = JSON.parse(req.body.data);
        const { habitId } = parsed;

        if (userId && habitId != null) {
            await pool.query('SELECT delete_streak($1, $2)', [habitId, userId]);
            return res.json({ success: true });
        } else {
            return res.status(400).json({ message: 'Missing streakID or user not authenticated' });
        }
    } catch (error) {
        console.error("Error deleting streak:", error);
        return res.status(500).json({ success: false, error: "Server error" });
    }
};

router.post('/', async (req, res) => {
    const { action } = req.body;

    if (action === 'getStreaks') {
        return getStreaks(req, res);
    } else if (action === 'updateStreak') {
        return updateStreak(req, res);
    } else if (action === 'incrementStreak') {
        return incrementStreak(req, res);
    } else if (action === 'deleteStreak') {
        return deleteStreak(req, res);
    }

    return res.status(400).json({ error: 'Invalid action' });
});


module.exports = router;


