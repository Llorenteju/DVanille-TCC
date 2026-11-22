const asyncHandler = require('../utils/asyncHandler');
const { sendSuccess } = require('../utils/response');
const service = require('../services/dietaryRestrictionService');

const listRestrictions = asyncHandler(async (_req, res) => {
  return sendSuccess(res, { data: await service.listRestrictions() });
});

module.exports = { listRestrictions };
