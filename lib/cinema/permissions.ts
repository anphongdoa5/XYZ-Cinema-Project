import type {Profile} from './types';
export const administratorSections=['phim','phong-chieu','lich-chieu','don-ve','khuyen-mai','bao-cao','tai-khoan','nhat-ky','mat-khau'];
export const employeeSections=['van-hanh','don-ve','kiem-soat','mat-khau'];
export function canOpenSection(role:Profile['role'],section:string){
 return (role==='admin'?administratorSections:role==='staff'?employeeSections:[]).includes(section);
}
export function internalHome(role:Profile['role']){return role==='staff'?'/admin/van-hanh':'/admin/lich-chieu';}
