export function isValidNumericId(id: string) {
    return /^[1-9][0-9]*$/.test(id);
}

export function isValidUuid(id: string) {
    return /^[0-9a-fA-F-]{36}$/.test(id);
}
