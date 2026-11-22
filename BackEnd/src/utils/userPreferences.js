/**
 * Preferências pessoais são informações opcionais e potencialmente sensíveis.
 * NUNCA incluí-las em listagens administrativas ou recomendações automáticas.
 */
const ALLOWED_DIETARY_PREFERENCES = Object.freeze([
  'Nenhuma',
  'Diabetes',
  'SOP',
  'Hipertensão',
  'SII',
  'Intolerância à Lactose',
  'Doença Celíaca',
  'Sensibilidade ao Glúten',
  'APLV',
  'Alergia a Oleaginosas',
  'Vegetariano',
  'Vegano',
  'Low Carb',
  'Outra',
]);

function isValidBirthDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return (
    !Number.isNaN(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value &&
    value >= '1900-01-01' &&
    value <= new Date().toISOString().slice(0, 10)
  );
}

function isValidDietaryPreferences(value) {
  if (!Array.isArray(value) || value.length > ALLOWED_DIETARY_PREFERENCES.length) return false;
  if (value.some((item) => typeof item !== 'string' || !ALLOWED_DIETARY_PREFERENCES.includes(item))) return false;
  const unique = new Set(value);
  if (unique.size !== value.length) return false;
  if (unique.has('Nenhuma') && unique.size > 1) return false;
  return true;
}

function hasPreferenceFields(input) {
  return ['birthDate', 'dietaryPreferences', 'notificationsOptIn']
    .some((field) => Object.prototype.hasOwnProperty.call(input, field));
}

function toPreferenceDatabaseFields(input) {
  const data = {};
  if (Object.prototype.hasOwnProperty.call(input, 'birthDate')) {
    data.birthDate = input.birthDate ? new Date(`${input.birthDate}T00:00:00.000Z`) : null;
  }
  if (Object.prototype.hasOwnProperty.call(input, 'dietaryPreferences')) {
    data.dietaryPreferences = input.dietaryPreferences;
  }
  if (Object.prototype.hasOwnProperty.call(input, 'notificationsOptIn')) {
    data.notificationsOptIn = input.notificationsOptIn;
  }
  return data;
}

function toPreferenceResponse(record) {
  return {
    birthDate: record?.birthDate ? new Date(record.birthDate).toISOString().slice(0, 10) : null,
    dietaryPreferences: record?.dietaryPreferences || [],
    notificationsOptIn: record?.notificationsOptIn ?? false,
    updatedAt: record?.updatedAt ?? null,
  };
}

module.exports = {
  ALLOWED_DIETARY_PREFERENCES,
  isValidBirthDate,
  isValidDietaryPreferences,
  hasPreferenceFields,
  toPreferenceDatabaseFields,
  toPreferenceResponse,
};
