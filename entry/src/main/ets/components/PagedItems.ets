// ArkUI IDataSource adapter shared by paged community lists.
export class PagedItems<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): T { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener); }
  append(items: T[]): void {
    const first = this.items.length; this.items = this.items.concat(items);
    for (let index = first; index < this.items.length; ++index) this.listeners.forEach((listener: DataChangeListener) => { listener.onDataAdd(index); });
  }
  replace(items: T[]): void { this.items = items.slice(); this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); }); }
  clear(): void { this.items = []; this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); }); }
}
