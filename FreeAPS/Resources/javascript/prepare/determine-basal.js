//для enact/smb-suggested.json параметры: monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json settings/autosens.json --meal monitor/meal.json --microbolus --reservoir monitor/reservoir.json

function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = false, reservoir = null, clock = new Date(), pump_history) {

    try {
        var middlewareReason = middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock, pump_history);
        console.log("Middleware reason: " + (middlewareReason || "Nothing changed"));
    } catch (error) {
        console.log("Invalid middleware: " + error);
    }

    var glucose_status = freeaps_glucoseGetLast(glucose);
    var autosens_data = null;

    if (autosens) {
        autosens_data = autosens;
    }

    var reservoir_data = null;
    if (reservoir) {
        reservoir_data = reservoir;
    }

    var meal_data = {};
    if (meal) {
        meal_data = meal;
        try {
            // Bridge fields from Swift meal output to any expected aliases
            if (typeof meal_data.mealCOB === 'number') {
                if (typeof meal_data.cob === 'undefined') meal_data.cob = meal_data.mealCOB;
                if (typeof meal_data.COB === 'undefined') meal_data.COB = meal_data.mealCOB;
            }
            if (typeof meal_data.carbs === 'number') {
                if (typeof meal_data.nsCarbs === 'undefined') meal_data.nsCarbs = meal_data.carbs;
            }
            // Normalize lastCarbTime to epoch ms for arithmetic in determine-basal
            if (meal_data.lastCarbTime !== undefined && meal_data.lastCarbTime !== null) {
                var ms = null;
                if (typeof meal_data.lastCarbTime === 'number') {
                    ms = meal_data.lastCarbTime;
                } else if (typeof meal_data.lastCarbTime === 'string') {
                    var parsed = Date.parse(meal_data.lastCarbTime);
                    if (!isNaN(parsed)) ms = parsed;
                } else if (typeof meal_data.lastCarbTime === 'object' && typeof meal_data.lastCarbTime.date === 'string') {
                    var parsed2 = Date.parse(meal_data.lastCarbTime.date);
                    if (!isNaN(parsed2)) ms = parsed2;
                }
                if (ms !== null) meal_data.lastCarbTime = ms;
            }
            // Ensure numeric types where needed
            if (typeof meal_data.mealCOB === 'string') {
                var mc = Number(meal_data.mealCOB);
                if (!isNaN(mc)) meal_data.mealCOB = mc;
            }
            if (typeof meal_data.carbs === 'string') {
                var cb = Number(meal_data.carbs);
                if (!isNaN(cb)) meal_data.carbs = cb;
            }
            console.log("determine-basal.prepare: meal_data=" + JSON.stringify(meal_data));
        } catch (e) {
            console.log("determine-basal.prepare: meal_data log error: " + e);
        }
    }

    return freeaps_determineBasal(glucose_status, currenttemp, iob, profile, autosens_data, meal_data, freeaps_basalSetTemp, microbolusAllowed, reservoir_data, clock);
}
